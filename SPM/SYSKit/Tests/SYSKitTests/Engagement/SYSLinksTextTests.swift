import XCTest
@testable import SYSKit

final class SYSLinksTextTests: XCTestCase {
    func testEveryLanguageHasEveryWord() {
        for (language, text) in SYSLinksText.translations {
            let words = [text.about, text.support, text.privacy, text.terms, text.website, text.get, text.open]
            XCTAssertFalse(words.contains { $0.isEmpty }, "\(language) has an empty word")
        }
    }

    func testEnglishIsTheFallback() {
        XCTAssertEqual(SYSLinksText.forLanguages(["xx"]), SYSLinksText())
    }

    func testThePortfolioLanguagesAreCovered() {
        let covered = Set(SYSLinksText.translations.keys)
        let used = ["en", "hi", "gu", "de", "es", "fr", "it", "pt-BR", "nl", "pl", "ru", "tr", "id", "vi", "th", "ja", "ko", "zh-Hans", "zh-Hant", "ar"]
        XCTAssertTrue(Set(used).isSubset(of: covered))
    }

    func testLanguagesPickTheirOwnWords() {
        XCTAssertEqual(SYSLinksText.forLanguages(["fr"]).privacy, "Politique de confidentialité")
        XCTAssertEqual(SYSLinksText.forLanguages(["zh-Hans"]).get, "获取")
    }
}
