import XCTest
@testable import SYSKit

final class SYSUpdateReminderTests: XCTestCase {
    private func config(version: String, recommended: String) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(version: version))
        let json = #"{"update":{"recommendedVersion":"\#(recommended)"}}"#
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    private func settings() throws -> SYSSettings {
        let name = "SYSUpdateReminderTests.\(UUID().uuidString)"
        return SYSSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: name)))
    }

    func testAnOlderAppIsRemindedOfTheRecommendedVersion() throws {
        let sut = SYSUpdateReminder.pending(config: config(version: "1.0.0", recommended: "2.0.0"), settings: try settings())
        XCTAssertEqual(sut?.version, "2.0.0")
    }

    func testACurrentAppIsNotReminded() throws {
        let current = config(version: "2.0.0", recommended: "2.0.0")
        XCTAssertNil(SYSUpdateReminder.pending(config: current, settings: try settings()))
    }

    func testASkippedVersionIsNotOfferedAgainButANewerOneIs() throws {
        let store = try settings()
        let key = SYSSettingsKey<String?>("sys.update.skippedVersion", default: nil)
        store[key] = "2.0.0"
        let skipped = config(version: "1.0.0", recommended: "2.0.0")
        XCTAssertNil(SYSUpdateReminder.pending(config: skipped, settings: store))
        let newer = config(version: "1.0.0", recommended: "2.1.0")
        XCTAssertEqual(SYSUpdateReminder.pending(config: newer, settings: store)?.version, "2.1.0")
    }

    func testEveryTranslationIsComplete() {
        for (language, text) in SYSUpdateReminderText.translations {
            XCTAssertFalse(text.title.isEmpty || text.message.isEmpty || text.update.isEmpty || text.skip.isEmpty, language)
        }
    }

    func testTheDeviceLanguageDecidesTheWords() {
        XCTAssertEqual(SYSUpdateReminderText.forLanguages(["de-DE"]).update, "Aktualisieren")
        XCTAssertEqual(SYSUpdateReminderText.forLanguages(["zh-Hant-TW"]).update, "更新")
        XCTAssertEqual(SYSUpdateReminderText.forLanguages(["pt-BR"]).update, "Atualizar")
        XCTAssertEqual(SYSUpdateReminderText.forLanguages(["xx"]).update, "Update")
    }
}
