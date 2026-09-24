import Foundation
// URLSession and HTTPURLResponse live in FoundationNetworking on Linux, not
// Foundation. Without this SYSKit builds on Apple platforms and fails on the
// Linux runner its tests are meant to be cheap on.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SYSNetworkError: Error, Equatable {
    case badURL
    case offline
    case notModified
    case http(status: Int)
    case decoding(String)
}

/// The one networking path every app uses.
///
/// Built for what these apps actually do: pull JSON and files from Firebase
/// Hosting and Storage. No general-purpose HTTP client, no request builders —
/// a fetch, a download, and the two things that make them behave well on a
/// phone: ETags and retries.
public actor SYSNetwork {
    public static let shared = SYSNetwork()

    private let session: URLSession
    private let maxRetries: Int

    public init(session: URLSession = .shared, maxRetries: Int = 2) {
        self.session = session
        self.maxRetries = maxRetries
    }

    // MARK: JSON

    /// Fetches and decodes JSON.
    ///
    /// Pass the `etag` from a previous call and an unchanged resource comes back
    /// as `.notModified` having transferred nothing. Every app polls config on
    /// every launch, so this is free bandwidth back.
    public func get<T: Decodable>(
        _ url: URL,
        as type: T.Type,
        etag: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> (value: T, etag: String?) {
        let (data, response) = try await load(url, etag: etag, timeout: timeout)
        do {
            return (try JSONDecoder().decode(T.self, from: data), response.etag)
        } catch {
            throw SYSNetworkError.decoding(String(describing: error))
        }
    }

    /// Raw bytes, same ETag handling.
    public func data(
        _ url: URL,
        etag: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> (data: Data, etag: String?) {
        let (data, response) = try await load(url, etag: etag, timeout: timeout)
        return (data, response.etag)
    }

    // MARK: Files

    /// Downloads to a temporary file instead of memory.
    ///
    /// Content packs are zips, and holding one as `Data` works fine right up
    /// until a pack gets big enough that it doesn't.
    public func download(_ url: URL, timeout: TimeInterval = 120) async throws -> URL {
        // Same as `load`: a local site is read, not fetched. Copied to a
        // temporary file because the caller owns what it gets back and will
        // move or delete it — handing back the staged original would consume
        // the site a page at a time.
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SYSNetworkError.http(status: 404)
            }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        do {
            let (fileURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else { return fileURL }
            guard 200 ..< 300 ~= http.statusCode else {
                throw SYSNetworkError.http(status: http.statusCode)
            }
            return fileURL
        } catch let error as SYSNetworkError {
            throw error
        } catch {
            throw Self.isOffline(error) ? SYSNetworkError.offline : error
        }
    }

    // MARK: Firebase Storage

    /// Builds a public download URL for a Firebase Storage object.
    ///
    /// The path must be encoded with `/` as `%2F` — Storage returns 404 for the
    /// unescaped form, which is a confusing way to spend an afternoon. Requires
    /// the object to be publicly readable, which is right for shipped content
    /// and wrong for anything per-user.
    public nonisolated static func storageURL(bucket: String, path: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded)?alt=media")
    }

    // MARK: Internals

    private func load(
        _ url: URL,
        etag: String?,
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        // A file URL is a site staged on this machine — see
        // `SYSHosting.localContentURL`. `URLSession` does not serve file URLs
        // through `data(for:)`, and the failure is an opaque "unsupported URL"
        // rather than anything that names the cause.
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else {
                throw SYSNetworkError.http(status: 404)
            }
            // ETags are for saving a round trip. Reading a local file has none
            // to save, so every read is a fresh one.
            guard let response = HTTPURLResponse(url: url, statusCode: 200,
                                                 httpVersion: nil, headerFields: nil) else {
                throw SYSNetworkError.http(status: -1)
            }
            return (data, response)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw SYSNetworkError.http(status: -1)
                }
                if http.statusCode == 304 { throw SYSNetworkError.notModified }
                guard 200 ..< 300 ~= http.statusCode else {
                    throw SYSNetworkError.http(status: http.statusCode)
                }
                return (data, http)
            } catch let error as SYSNetworkError {
                // Only transient server failures are worth retrying. A 404 will
                // still be a 404 in two seconds.
                guard case .http(let status) = error, status >= 500, attempt < maxRetries else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt))
            } catch {
                if Self.isOffline(error) { throw SYSNetworkError.offline }
                guard attempt < maxRetries else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt))
            }
        }
    }

    /// 0.5s, 1s, 2s …
    static func backoff(_ attempt: Int) -> UInt64 {
        UInt64(Double(NSEC_PER_SEC) * 0.5 * pow(2, Double(attempt - 1)))
    }

    /// Whether this is "the server could not be reached" — one thing to the
    /// person holding the phone, however many ways it happens (timeout,
    /// unresolvable host, refused connection, a portal swallowing DNS...).
    private static func isOffline(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return [NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDataNotAllowed,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorInternationalRoamingOff].contains(code)
    }
}

private extension HTTPURLResponse {
    var etag: String? { value(forHTTPHeaderField: "Etag") }
}
