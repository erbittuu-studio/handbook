import XCTest
@testable import SYSKit

final class SYSDeepLinkBuildTests: XCTestCase {
    func testURLIsBuiltFromSchemeHostAndPath() {
        XCTAssertEqual(SYSDeepLink.url(scheme: "demo", host: "pack", path: "7")?.absoluteString, "demo://pack/7")
    }

    func testABundleWithoutURLTypesHasNoScheme() {
        XCTAssertNil(SYSDeepLink.scheme(bundle: Bundle(for: SYSDeepLinkBuildTests.self)))
    }

    func testTargetSplitsKindAndID() throws {
        let url = try XCTUnwrap(URL(string: "demo://Festival/diwali_2026"))
        XCTAssertEqual(SYSDeepLink.target(of: url, scheme: "demo"), SYSDeepLink.Target(kind: "festival", id: "diwali_2026"))
    }

    func testTargetWithoutAnIDHasNone() throws {
        let url = try XCTUnwrap(URL(string: "demo://calendar"))
        XCTAssertEqual(SYSDeepLink.target(of: url, scheme: "demo"), SYSDeepLink.Target(kind: "calendar", id: nil))
    }

    func testTargetDecodesPercentEscapes() throws {
        let url = try XCTUnwrap(URL(string: "demo://festival/ganesha_%28jayanti%29"))
        XCTAssertEqual(SYSDeepLink.target(of: url, scheme: "demo")?.id, "ganesha_(jayanti)")
    }

    func testTargetIgnoresAnotherScheme() throws {
        let url = try XCTUnwrap(URL(string: "other://pack/7"))
        XCTAssertNil(SYSDeepLink.target(of: url, scheme: "demo"))
    }
}
