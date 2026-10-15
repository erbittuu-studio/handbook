import XCTest
@testable import SYSKit

final class SYSDailyRotationTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEmptyListGivesNothing() {
        XCTAssertNil(SYSDailyRotation.pick([Int](), on: date(2026, 1, 1), calendar: calendar))
    }

    func testFirstDayOfTheYearIsTheFirstItem() {
        XCTAssertEqual(SYSDailyRotation.pick(["a", "b", "c"], on: date(2026, 1, 1), calendar: calendar), "a")
    }

    func testTheSameItemAllDay() {
        let morning = SYSDailyRotation.pick(["a", "b", "c"], on: date(2026, 3, 5, hour: 6), calendar: calendar)
        let night = SYSDailyRotation.pick(["a", "b", "c"], on: date(2026, 3, 5, hour: 23), calendar: calendar)
        XCTAssertEqual(morning, night)
    }

    func testNextDayMovesToTheNextItemAndWrapsAround() {
        let items = ["a", "b", "c"]
        XCTAssertEqual(SYSDailyRotation.pick(items, on: date(2026, 1, 2), calendar: calendar), "b")
        XCTAssertEqual(SYSDailyRotation.pick(items, on: date(2026, 1, 3), calendar: calendar), "c")
        XCTAssertEqual(SYSDailyRotation.pick(items, on: date(2026, 1, 4), calendar: calendar), "a")
    }

    func testANewYearStartsOverAtTheFirstItem() {
        let items = ["a", "b", "c", "d"]
        XCTAssertEqual(SYSDailyRotation.pick(items, on: date(2027, 1, 1), calendar: calendar), "a")
    }
}
