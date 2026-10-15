#if canImport(UserNotifications) && !os(watchOS)
import UserNotifications
import XCTest
@testable import SYSKit

@MainActor
final class SYSNotificationBudgetTests: XCTestCase {
    private func plan(_ days: [Int]) -> [SYSPlannedNotification] {
        days.map {
            SYSPlannedNotification(
                id: "n\($0)",
                fireDate: Date(timeIntervalSince1970: TimeInterval($0) * 86_400),
                components: DateComponents(day: $0),
                content: UNMutableNotificationContent()
            )
        }
    }

    func testEarliestComeFirst() {
        let kept = SYSNotifications.withinBudget(plan([3, 1, 2]), others: 0, reserved: 0)
        XCTAssertEqual(kept.map(\.id), ["n1", "n2", "n3"])
    }

    func testOtherPendingAndReservedSlotsAreSubtracted() {
        let limit = SYSNotifications.pendingLimit
        let days = Array(1...(limit + 10))
        let kept = SYSNotifications.withinBudget(plan(days), others: 1, reserved: 3)
        XCTAssertEqual(kept.count, limit - 4)
        XCTAssertEqual(kept.first?.id, "n1")
    }

    func testNeverNegative() {
        XCTAssertTrue(SYSNotifications.withinBudget(plan([1]), others: 100, reserved: 5).isEmpty)
    }
}
#endif
