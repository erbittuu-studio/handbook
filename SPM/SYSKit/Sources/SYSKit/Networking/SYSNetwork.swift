import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SYSNetworkError: Error, Equatable {
    case badURL
    case offline
    case notModified
    case http(status: Int)
    case decoding(String)
}

actor SYSNetwork {
    static let shared = SYSNetwork()

    private let session: URLSession
    private let maxRetries: Int

    init(session: URLSession = .shared, maxRetries: Int = 2) {
        self.session = session
        self.maxRetries = maxRetries
    }

    func get<T: Decodable>(
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

    func data(
        _ url: URL,
        etag: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> (data: Data, etag: String?) {
        let (data, response) = try await load(url, etag: etag, timeout: timeout)
        return (data, response.etag)
    }

    func download(_ url: URL, timeout: TimeInterval = 120) async throws -> URL {
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

        var attempt = 0
        while true {
            do {
                let (fileURL, response) = try await session.download(for: request)
                guard let http = response as? HTTPURLResponse else { return fileURL }
                guard 200 ..< 300 ~= http.statusCode else {
                    try? FileManager.default.removeItem(at: fileURL)
                    throw SYSNetworkError.http(status: http.statusCode)
                }
                return fileURL
            } catch let error as SYSNetworkError {
                guard case .http(let status) = error, status >= 500, attempt < maxRetries else { throw error }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                guard attempt < maxRetries else {
                    throw Self.isOffline(error) ? SYSNetworkError.offline : error
                }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt))
            }
        }
    }

    nonisolated static func storageURL(bucket: String, path: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded)?alt=media")
    }

    private func load(
        _ url: URL,
        etag: String?,
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else {
                throw SYSNetworkError.http(status: 404)
            }
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

    static func backoff(_ attempt: Int) -> UInt64 {
        UInt64(Double(NSEC_PER_SEC) * 0.5 * pow(2, Double(attempt - 1)))
    }

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
