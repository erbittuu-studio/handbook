import XCTest
@testable import SYSKit

final class SYSDeepLinkBuildTests: XCTestCase {
    func testURLIsBuiltFromSchemeHostAndPath() {
        XCTAssertEqual(SYSDeepLink.url(scheme: "demo", host: "pack", path: "7")?.absoluteString, "demo://pack/7")
    }

    func testABundleWithoutURLTypesHasNoScheme() {
        XCTAssertNil(SYSDeepLink.scheme(bundle: Bundle(for: SYSDeepLinkBuildTests.self)))
    }
}
