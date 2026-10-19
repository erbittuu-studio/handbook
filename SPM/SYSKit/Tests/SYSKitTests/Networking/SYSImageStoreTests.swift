#if canImport(UIKit) && !os(watchOS)
import UIKit
import XCTest
@testable import SYSKit

private final class ImageStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (status: Int, body: Data, tag: String?)?
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.requests += 1
        guard let stub = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var headers: [String: String] = [:]
        if let tag = stub.tag { headers["Etag"] = tag }
        let http = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class SYSImageStoreTests: XCTestCase {
    private var directory: URL!
    private let address = URL(string: "https://example.com/pictures/one.png")!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ImageStub.response = nil
        ImageStub.requests = 0
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(recheckAfter: TimeInterval = 86_400, limit: Int = 300_000_000) -> SYSImageStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStub.self]
        return SYSImageStore(
            directory: directory,
            network: SYSNetwork(session: URLSession(configuration: configuration), maxRetries: 0),
            limitBytes: limit,
            recheckAfter: recheckAfter
        )
    }

    private func png(width: Int = 600, height: Int = 300) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testAKeptPictureStillShowsOfflineAfterARelaunch() async throws {
        ImageStub.response = (200, png(), "v1")
        _ = try await store().image(for: address, maxPixelSize: 512)

        ImageStub.response = nil
        let relaunched = store()
        let image = try await relaunched.image(for: address, maxPixelSize: 512)
        XCTAssertGreaterThan(image.size.width, 0)
        let cached = await relaunched.isCached(address)
        XCTAssertTrue(cached)
    }

    func testNothingKeptAndNoConnectionReportsOffline() async {
        do {
            _ = try await store().image(for: address, maxPixelSize: 512)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SYSImageError, .offline)
        }
    }

    func testAFailedRefreshKeepsThePictureAlreadyOnTheDevice() async throws {
        ImageStub.response = (200, png(), "v1")
        _ = try await store().image(for: address, maxPixelSize: 512)

        ImageStub.response = (500, Data(), nil)
        let again = store(recheckAfter: 0)
        let image = try await again.image(for: address, maxPixelSize: 512)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(image.size.width, 0)
        let cached = await again.isCached(address)
        XCTAssertTrue(cached)
    }

    func testSomethingThatIsNotAPictureIsNeverKept() async {
        ImageStub.response = (200, Data("<html>blocked</html>".utf8), nil)
        let sut = store()
        do {
            _ = try await sut.image(for: address, maxPixelSize: 512)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SYSImageError, .failed)
        }
        let cached = await sut.isCached(address)
        XCTAssertFalse(cached)
    }

    func testAPictureIsNeverScaledUp() async throws {
        let file = directory.appendingPathComponent("local.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(width: 600, height: 300).write(to: file)
        let image = try await store().image(for: file, maxPixelSize: 2048)
        XCTAssertEqual(Int(image.size.width), 600)
    }

    func testAPictureIsScaledDownToTheRequestedSize() async throws {
        let file = directory.appendingPathComponent("big.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(width: 1200, height: 600).write(to: file)
        let image = try await store().image(for: file, maxPixelSize: 256)
        XCTAssertEqual(Int(image.size.width), 256)
    }

    func testPrefetchOnlyStoresWhenOnline() async {
        ImageStub.response = (200, png(), "v1")
        let sut = store()
        let allowed = await MainActor.run { SYSConnectivity.shared.allowsOptionalDownloads }
        await sut.prefetch([address])
        let cached = await sut.isCached(address)
        XCTAssertEqual(cached, allowed)
    }

    func testTheOldestPicturesGoFirstWhenTheStoreIsFull() async throws {
        ImageStub.response = (200, png(), "v1")
        let sut = store(limit: 1)
        let addresses = (0..<20).map { URL(string: "https://example.com/p\($0).png")! }
        for url in addresses { _ = try await sut.image(for: url, maxPixelSize: 256) }
        let first = await sut.isCached(addresses[0])
        let last = await sut.isCached(addresses[19])
        XCTAssertFalse(first)
        XCTAssertTrue(last)
    }
}
#endif
