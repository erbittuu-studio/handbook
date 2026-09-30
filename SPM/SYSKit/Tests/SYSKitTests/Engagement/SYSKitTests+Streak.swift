import XCTest
@testable import SYSKit

@MainActor
final class SYSStreakTests: XCTestCase {
    private func makeStreak(now: @escaping () -> Date) -> SYSStreak {
        let suffix = UUID().uuidString
        return SYSStreak(
            countKey: SYSSettingsKey<Int>("test.streak.count.\(suffix)", default: 0),
            lastDateKey: SYSSettingsKey<Date?>("test.streak.lastDate.\(suffix)", default: nil),
            now: now
        )
    }

    private static let day: TimeInterval = 86400

    func testFirstEverRecordStartsAtOne() {
        let streak = makeStreak(now: { Date() })
        XCTAssertEqual(streak.count, 0)
        XCTAssertEqual(streak.recordToday(), 1)
        XCTAssertTrue(streak.isActive)
    }

    func testRecordingTwiceTheSameDayDoesNotDoubleCount() {
        let today = Date()
        let streak = makeStreak(now: { today })
        streak.recordToday()
        streak.recordToday()
        XCTAssertEqual(streak.count, 1)
    }

    func testConsecutiveDayExtendsTheStreak() {
        var current = Date()
        let streak = makeStreak(now: { current })
        streak.recordToday()
        current = current.addingTimeInterval(Self.day)
        XCTAssertEqual(streak.recordToday(), 2)
        current = current.addingTimeInterval(Self.day)
        XCTAssertEqual(streak.recordToday(), 3)
    }

    func testGapOfMoreThanADayResetsToOne() {
        var current = Date()
        let streak = makeStreak(now: { current })
        streak.recordToday()
        current = current.addingTimeInterval(Self.day)
        streak.recordToday()
        XCTAssertEqual(streak.count, 2)

        current = current.addingTimeInterval(Self.day * 3) // a gap, not consecutive
        XCTAssertEqual(streak.recordToday(), 1)
    }

    func testIsActiveOnTheRecordedDayAndTheDayAfter() {
        var current = Date()
        let streak = makeStreak(now: { current })
        streak.recordToday()
        XCTAssertTrue(streak.isActive, "still active the same day")

        current = current.addingTimeInterval(Self.day)
        XCTAssertTrue(streak.isActive, "still active the next day — the grace window before it breaks")

        current = current.addingTimeInterval(Self.day)
        XCTAssertFalse(streak.isActive, "two days with nothing recorded — the streak has broken")
    }

    func testIsActiveIsFalseWithNothingEverRecorded() {
        let streak = makeStreak(now: { Date() })
        XCTAssertFalse(streak.isActive)
    }
}
