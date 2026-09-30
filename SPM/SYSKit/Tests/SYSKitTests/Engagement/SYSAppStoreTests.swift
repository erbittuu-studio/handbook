import XCTest
@testable import SYSKit

final class SYSAppStoreTests: XCTestCase {
    func testStoreURLUsesTheAppID() {
        XCTAssertEqual(SYSAppStore.url(id: "123")?.absoluteString, "https://apps.apple.com/app/id123")
    }

    func testReviewURLAsksForTheReviewSheet() {
        XCTAssertEqual(
            SYSAppStore.reviewURL(id: "123")?.absoluteString,
            "https://apps.apple.com/app/id123?action=write-review"
        )
    }

    func testAppNameIsNeverNil() {
        XCTAssertNotNil(SYSAbout.appName(bundle: Bundle(for: SYSAppStoreTests.self)))
    }
}
