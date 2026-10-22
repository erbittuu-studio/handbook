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

private let sysResumePiece: Int64 = 2 * 1024 * 1024

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

    /// Downloads `url` into `partial`, a piece at a time, so a download that is cut off keeps what arrived and the
    /// next call continues from there. A server that ignores ranges sends the whole file, which is written from the
    /// start. The caller removes `partial` once it has used it.
    func download(
        _ url: URL,
        into partial: URL,
        timeout: TimeInterval = 120,
        progress: (@Sendable (_ received: Int64, _ total: Int64) -> Void)? = nil
    ) async throws -> URL {
        if SYSDebugRoute.forcesOffline, !url.isFileURL { throw SYSNetworkError.offline }
        let fm = FileManager.default
        try fm.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        if url.isFileURL {
            guard fm.fileExists(atPath: url.path) else { throw SYSNetworkError.http(status: 404) }
            try? fm.removeItem(at: partial)
            try fm.copyItem(at: url, to: partial)
            return partial
        }

        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }
        var offset = Int64(try handle.seekToEnd())
        var total: Int64?
        var restarted = false

        while total == nil || offset < total! {
            do {
                let (data, response) = try await load(
                    url, etag: nil, timeout: timeout, range: "bytes=\(offset)-\(offset + sysResumePiece - 1)")
                if response.statusCode == 206, let range = Self.contentRange(response), range.first == offset {
                    try handle.write(contentsOf: data)
                    offset += Int64(data.count)
                    total = range.total
                } else {
                    try handle.truncate(atOffset: 0)
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: data)
                    offset = Int64(data.count)
                    total = offset
                }
                progress?(offset, total ?? offset)
            } catch SYSNetworkError.http(status: 416) {
                guard !restarted else { throw SYSNetworkError.http(status: 416) }
                restarted = true
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
                offset = 0
                total = nil
            }
        }
        return partial
    }

    private static func contentRange(_ response: HTTPURLResponse) -> (first: Int64, total: Int64)? {
        guard let header = response.value(forHTTPHeaderField: "Content-Range"),
              header.hasPrefix("bytes ") else { return nil }
        let parts = header.dropFirst(6).split(whereSeparator: { $0 == "-" || $0 == "/" })
        guard parts.count == 3, let first = Int64(parts[0]), let total = Int64(parts[2]) else { return nil }
        return (first, total)
    }

    private func load(
        _ url: URL,
        etag: String?,
        timeout: TimeInterval,
        range: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        if SYSDebugRoute.forcesOffline, !url.isFileURL { throw SYSNetworkError.offline }
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
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }

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

    private static func hasNoConnection(_ error: Error) -> Bool {
        let code = (error as NSError).code
        return [NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff].contains(code)
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
