import XCTest
@testable import SYSKit

final class SYSLaunchBlockerTests: XCTestCase {
    private let text = SYSLaunchBlockerText(appName: "Kiddo")

    func testMaintenanceUsesTheServerMessageWhenThereIsOne() {
        let served = SYSLaunchBlockerContent(state: .maintenance(message: "Back at 9"), text: text)
        XCTAssertEqual(served?.message, "Back at 9")
        XCTAssertEqual(served?.title, "Back Soon")
        let fallback = SYSLaunchBlockerContent(state: .maintenance(message: nil), text: text)
        XCTAssertEqual(fallback?.message, text.maintenanceMessage)
        XCTAssertTrue(text.maintenanceMessage.contains("Kiddo"))
    }

    func testUpdateRequiredAndOfflineHaveTheirOwnSymbols() {
        let update = SYSLaunchBlockerContent(state: .updateRequired(message: nil, storeURL: nil), text: text)
        XCTAssertEqual(update?.symbol, "arrow.down.circle.fill")
        XCTAssertEqual(update?.title, "Time to Update")
        let offline = SYSLaunchBlockerContent(state: .dataUnavailable(.notConfigured), text: text)
        XCTAssertEqual(offline?.symbol, "wifi.exclamationmark")
        XCTAssertTrue(offline?.message.contains("Kiddo") == true)
    }

    func testOnlyTheBlockingStatesProduceContent() {
        XCTAssertNil(SYSLaunchBlockerContent(state: .ready, text: text))
        XCTAssertNil(SYSLaunchBlockerContent(state: .onboarding, text: text))
        XCTAssertNil(SYSLaunchBlockerContent(state: .whatsNew(["x"]), text: text))
    }

    func testIsBlockingAgreesWithContent() {
        let states: [SYSAppState] = [
            .maintenance(message: nil),
            .updateRequired(message: nil, storeURL: nil),
            .dataUnavailable(.notConfigured),
            .onboarding,
            .whatsNew([]),
            .ready
        ]
        for state in states {
            XCTAssertEqual(state.isBlocking, SYSLaunchBlockerContent(state: state, text: text) != nil)
        }
    }

    func testEveryStringCanBeReplacedForLocalization() {
        let custom = SYSLaunchBlockerText(
            appName: "Kiddo",
            maintenanceTitle: "Bientôt",
            offlineMessage: "Internet nécessaire",
            retry: "Réessayer"
        )
        XCTAssertEqual(custom.maintenanceTitle, "Bientôt")
        XCTAssertEqual(custom.offlineMessage, "Internet nécessaire")
        XCTAssertEqual(custom.retry, "Réessayer")
        XCTAssertEqual(custom.update, "Update")
    }
}
