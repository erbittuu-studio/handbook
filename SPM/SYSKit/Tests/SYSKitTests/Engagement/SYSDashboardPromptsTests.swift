import UserNotifications
import XCTest
@testable import SYSKit

final class SYSDashboardPromptsTests: XCTestCase {
    private func due(launch: Int = 3, minLaunch: Int = 3, wanted: Bool = true, status: UNAuthorizationStatus = .notDetermined) -> Bool {
        SYSNotificationPrompt.isDue(launchCount: launch, minLaunch: minLaunch, wanted: wanted, status: status)
    }

    func testAsksOnceTheMinimumLaunchIsReached() {
        XCTAssertFalse(due(launch: 2))
        XCTAssertTrue(due(launch: 3))
        XCTAssertTrue(due(launch: 9))
    }

    func testNeverAsksAfterTheSystemWasAsked() {
        for status: UNAuthorizationStatus in [.authorized, .denied, .provisional] {
            XCTAssertFalse(due(status: status))
        }
    }

    func testStaysQuietWhenTheAppDoesNotWantReminders() {
        XCTAssertFalse(due(wanted: false))
    }
}
