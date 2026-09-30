import XCTest
@testable import SYSKit

final class SYSLocalizedTextTests: XCTestCase {
    private let text = SYSLocalizedText(["en": "Apple", "hi": "सेब"])

    func testTextPicksTheRequestedLanguage() {
        XCTAssertEqual(text.text(for: ["hi"]), "सेब")
    }

    func testTextFallsBackToEnglish() {
        XCTAssertEqual(text.text(for: ["gu"]), "Apple")
    }

    func testTextIsEmptyWhenNothingWasProvided() {
        XCTAssertEqual(SYSLocalizedText([:]).text(for: ["en"]), "")
    }

    func testEqualTextHashesAlike() {
        XCTAssertEqual(Set([text, SYSLocalizedText(["hi": "सेब", "en": "Apple"])]).count, 1)
    }

    func testValuesAreReadable() {
        XCTAssertEqual(text.values["en"], "Apple")
    }
}
