#if os(iOS)
import XCTest
@testable import SYSKit

final class SYSOfflineTextTests: XCTestCase {
    private let appLanguages = [
        "en", "hi", "gu", "ar", "de", "es", "fr", "id", "it", "ja", "ko", "nl", "pl",
        "pt-BR", "ru", "th", "tr", "vi", "zh-Hans", "zh-Hant"
    ]

    func testEveryAppLanguageHasEveryWordOfTheContentNotice() {
        for language in appLanguages {
            let text = SYSContentNoticeText.forLanguages([language])
            let fields = [text.needsInternetTitle, text.needsInternetMessage, text.failedTitle,
                          text.failedMessage, text.loading, text.retry, text.ok]
            XCTAssertTrue(fields.allSatisfy { !$0.isEmpty }, language)
            if language != "en" {
                XCTAssertNotEqual(text.needsInternetTitle, SYSContentNoticeText().needsInternetTitle, language)
                XCTAssertNotEqual(text.failedMessage, SYSContentNoticeText().failedMessage, language)
            }
        }
    }

    func testEveryAppLanguageHasEveryWordOfTheOfflineNotice() {
        for language in appLanguages {
            let text = SYSOfflineText.forLanguages([language])
            XCTAssertTrue([text.title, text.message, text.partial].allSatisfy { !$0.isEmpty }, language)
            if language != "en" {
                XCTAssertNotEqual(text.title, SYSOfflineText().title, language)
                XCTAssertNotEqual(text.partial, SYSOfflineText().partial, language)
            }
        }
    }

    func testRegionalLanguageCodesFindTheirTranslation() {
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["zh-Hans-US"]).retry, "重试")
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["zh-Hant-TW"]).retry, "重試")
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["pt-PT"]).retry, "Tentar de novo")
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["fr-CA"]).retry, "Réessayer")
        XCTAssertEqual(SYSOfflineText.forLanguages(["de-AT"]).title, "Du bist offline")
    }

    func testAnUnknownLanguageFallsBackToEnglish() {
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["xx"]).retry, "Try again")
        XCTAssertEqual(SYSOfflineText.forLanguages(["xx"]).title, "You're offline")
    }

    func testTheFirstSupportedPreferredLanguageWins() {
        XCTAssertEqual(SYSContentNoticeText.forLanguages(["xx", "es-MX", "fr"]).retry, "Reintentar")
    }
}
#endif
