import XCTest
@testable import SYSKit

private final class RangeStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var servesRanges = true
    nonisolated(unsafe) static var failFrom: Int?
    nonisolated(unsafe) static var ranges: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let header = request.value(forHTTPHeaderField: "Range")
        Self.ranges.append(header ?? "none")
        if let failFrom = Self.failFrom, Self.ranges.count >= failFrom {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let total = Self.body.count
        var status = 200
        var headers: [String: String] = [:]
        var payload = Self.body
        if Self.servesRanges, let header, header.hasPrefix("bytes="),
           let (first, last) = Self.parse(String(header.dropFirst(6))) {
            if first >= total {
                status = 416
                headers["Content-Range"] = "bytes */\(total)"
                payload = Data()
            } else {
                let end = min(last, total - 1)
                status = 206
                headers["Content-Range"] = "bytes \(first)-\(end)/\(total)"
                payload = Self.body.subdata(in: first ..< end + 1)
            }
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func parse(_ value: String) -> (Int, Int)? {
        let parts = value.split(separator: "-")
        guard parts.count == 2, let first = Int(parts[0]), let last = Int(parts[1]) else { return nil }
        return (first, last)
    }
}

final class SYSNetworkResumeTests: XCTestCase {
    private let address = URL(string: "https://example.com/packs/one.zip")!
    private var directory: URL!
    private var network: SYSNetwork!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString)")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeStub.self]
        network = SYSNetwork(session: URLSession(configuration: configuration), maxRetries: 0)
        RangeStub.body = Data((0 ..< 5 * 1024 * 1024 + 123).map { UInt8($0 % 251) })
        RangeStub.servesRanges = true
        RangeStub.failFrom = nil
        RangeStub.ranges = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var partial: URL { directory.appendingPathComponent("one.part") }

    func testAFileArrivesInPieces() async throws {
        let file = try await network.download(address, into: partial)
        XCTAssertEqual(try Data(contentsOf: file), RangeStub.body)
        XCTAssertEqual(RangeStub.ranges.count, 3)
    }

    func testACutOffDownloadKeepsWhatArrivedAndAsksOnlyForTheRest() async throws {
        RangeStub.failFrom = 3
        do {
            _ = try await network.download(address, into: partial)
            XCTFail("the connection was cut")
        } catch {}
        let kept = try FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int
        XCTAssertEqual(kept, 4 * 1024 * 1024)

        RangeStub.failFrom = nil
        RangeStub.ranges = []
        let file = try await network.download(address, into: partial)
        XCTAssertEqual(RangeStub.ranges, ["bytes=4194304-6291455"])
        XCTAssertEqual(try Data(contentsOf: file), RangeStub.body)
    }

    func testAServerThatIgnoresRangesStillDeliversTheWholeFile() async throws {
        RangeStub.servesRanges = false
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 9, count: 100).write(to: partial)
        let file = try await network.download(address, into: partial)
        XCTAssertEqual(try Data(contentsOf: file), RangeStub.body)
    }

    func testAPartialFileAlreadyCompleteIsReplacedByAFreshCopy() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RangeStub.body.write(to: partial)
        let file = try await network.download(address, into: partial)
        XCTAssertEqual(try Data(contentsOf: file), RangeStub.body)
    }

    func testAProgressCallReportsBytesReceived() async throws {
        let seen = ProgressBox()
        _ = try await network.download(address, into: partial) { received, total in seen.add(received, total) }
        XCTAssertEqual(seen.last?.0, Int64(RangeStub.body.count))
        XCTAssertEqual(seen.last?.1, Int64(RangeStub.body.count))
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Int64, Int64)] = []
    func add(_ received: Int64, _ total: Int64) { lock.lock(); values.append((received, total)); lock.unlock() }
    var last: (Int64, Int64)? { lock.lock(); defer { lock.unlock() }; return values.last }
}
