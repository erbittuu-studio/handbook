import XCTest
@testable import SYSKit

final class SYSTallyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)) ?? Date()
    }

    private func key(_ day: Int) -> String { SYSTally.dayKey(date(day), calendar: calendar) }

    func testCountsRiseAndFallPerItemAndPerDay() {
        var tally = SYSTally()
        tally.add(54, to: "om", on: key(10), device: "phone")
        tally.add(10, to: "gayatri", on: key(10), device: "phone")
        tally.add(-4, to: "om", on: key(10), device: "phone")
        XCTAssertEqual(tally.total(of: "om"), 50)
        XCTAssertEqual(tally.total(of: "gayatri"), 10)
        XCTAssertEqual(tally.count(on: key(10)), 60)
        XCTAssertEqual(tally.count(of: "om", on: key(10)), 50)
    }

    func testTwoDevicesMergeWithoutLosingATap() {
        var phone = SYSTally()
        var watch = SYSTally()
        phone.add(30, to: "om", on: key(10), device: "phone")
        watch.add(12, to: "om", on: key(10), device: "watch")
        var merged = phone
        merged.merge(watch, today: key(10))
        var other = watch
        other.merge(phone, today: key(10))
        XCTAssertEqual(merged.total(of: "om"), 42)
        XCTAssertEqual(merged, other)
    }

    func testMergingTheSameStateAgainChangesNothing() {
        var phone = SYSTally()
        phone.add(30, to: "om", on: key(10), device: "phone")
        var watch = SYSTally()
        watch.add(5, to: "om", on: key(10), device: "watch")
        watch.merge(phone, today: key(10))
        let once = watch
        watch.merge(phone, today: key(10))
        XCTAssertEqual(watch, once)
    }

    func testAStaleCopyNeverRollsTheCountBack() {
        var phone = SYSTally()
        phone.add(10, to: "om", on: key(10), device: "phone")
        let old = phone
        phone.add(20, to: "om", on: key(10), device: "phone")
        phone.merge(old, today: key(10))
        XCTAssertEqual(phone.total(of: "om"), 30)
    }

    func testUndoOnOneDeviceSurvivesAMerge() {
        var phone = SYSTally()
        var watch = SYSTally()
        phone.add(5, to: "om", on: key(10), device: "phone")
        watch.merge(phone, today: key(10))
        watch.add(-1, to: "om", on: key(10), device: "watch")
        phone.merge(watch, today: key(10))
        XCTAssertEqual(phone.total(of: "om"), 4)
    }

    func testSettingATotalMovesItToThatNumber() {
        var tally = SYSTally()
        tally.add(50, to: "om", on: key(10), device: "phone")
        tally.setTotal(of: "om", to: 20, on: key(10), device: "phone")
        XCTAssertEqual(tally.total(of: "om"), 20)
        tally.setTotal(of: "om", to: -5, on: key(10), device: "phone")
        XCTAssertEqual(tally.total(of: "om"), 0)
    }

    func testStreakCountsConsecutiveDaysAndSurvivesAQuietToday() {
        var tally = SYSTally()
        for day in [7, 8, 9] { tally.add(1, to: "om", on: key(day), device: "phone") }
        XCTAssertEqual(tally.streak(today: date(9), calendar: calendar), 3)
        XCTAssertEqual(tally.streak(today: date(10), calendar: calendar), 3)
        XCTAssertEqual(tally.streak(today: date(11), calendar: calendar), 0)
    }

    func testAGapBreaksTheStreak() {
        var tally = SYSTally()
        for day in [5, 6, 8, 9] { tally.add(1, to: "om", on: key(day), device: "phone") }
        XCTAssertEqual(tally.streak(today: date(9), calendar: calendar), 2)
    }

    func testRecentDaysRunOldestToNewestWithZeros() {
        var tally = SYSTally()
        tally.add(3, to: "om", on: key(9), device: "phone")
        let recent = tally.recent(3, endingOn: date(10), calendar: calendar)
        XCTAssertEqual(recent.map(\.day), [key(8), key(9), key(10)])
        XCTAssertEqual(recent.map(\.count), [0, 3, 0])
    }

    func testOldDaysAreDroppedButTheTotalStays() {
        var tally = SYSTally()
        var day = date(10)
        for _ in 0..<(SYSTally.keptDays + 10) {
            tally.add(1, to: "om", on: SYSTally.dayKey(day, calendar: calendar), device: "phone")
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        XCTAssertLessThanOrEqual(tally.days.count, SYSTally.keptDays)
        XCTAssertEqual(tally.total(of: "om"), SYSTally.keptDays + 10)
    }

    func testTheDayKeyIsPaddedAndSortsInOrder() {
        XCTAssertEqual(SYSTally.dayKey(date(3), calendar: calendar), "2026-10-03")
        XCTAssertLessThan(key(3), key(10))
    }

    func testATallySurvivesAnEncodeAndDecode() throws {
        var tally = SYSTally()
        tally.add(7, to: "om", on: key(10), device: "phone")
        let decoded = try JSONDecoder().decode(SYSTally.self, from: JSONEncoder().encode(tally))
        XCTAssertEqual(decoded, tally)
    }
}

@MainActor
final class SYSTallyStoreTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = UUID().uuidString
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store() -> SYSTallyStore {
        SYSTallyStore(name: "jaap", defaults: suite, now: { Date(timeIntervalSince1970: 1_792_000_000) })
    }

    func testCountsAreSavedAndComeBackInANewStore() {
        let first = store()
        first.add(54, to: "om")
        first.add(-4, to: "om")
        XCTAssertEqual(store().total(of: "om"), 50)
        XCTAssertEqual(store().countToday, 50)
    }

    func testSettingATotalIsKept() {
        let first = store()
        first.add(30, to: "om")
        first.setTotal(of: "om", to: 12)
        XCTAssertEqual(store().total(of: "om"), 12)
    }

    func testWhatTheOtherDeviceCountedIsAddedToTheOwn() throws {
        let local = store()
        local.add(10, to: "om")
        var remote = SYSTally()
        remote.add(7, to: "om", on: local.today, device: "other-device")
        local.receive(try JSONEncoder().encode(remote))
        XCTAssertEqual(local.total(of: "om"), 17)
        XCTAssertEqual(store().total(of: "om"), 17)
    }

    func testAnOldCopyOfTheOwnCountChangesNothing() throws {
        let local = store()
        local.add(10, to: "om")
        let old = try JSONEncoder().encode(local.tally)
        local.add(5, to: "om")
        local.receive(old)
        XCTAssertEqual(local.total(of: "om"), 15)
    }

    func testAResetEmptiesTheCountsAndTheyStayEmpty() async throws {
        let local = store()
        local.add(9, to: "om")
        suite.removePersistentDomain(forName: suiteName)
        NotificationCenter.default.post(name: .sysDidReset, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(local.total(of: "om"), 0)
    }

    func testUnreadableDataIsIgnored() {
        let local = store()
        local.add(3, to: "om")
        local.receive(Data("nonsense".utf8))
        XCTAssertEqual(local.total(of: "om"), 3)
    }
}

@MainActor
final class SYSSyncedSettingsTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName = ""
    private var clock = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUp() {
        super.setUp()
        suiteName = UUID().uuidString
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func settings() -> SYSSyncedSettings {
        SYSSyncedSettings(name: "jaap", defaults: suite, now: { self.clock })
    }

    private func payload(_ value: String, at stamp: Date) throws -> Data {
        try JSONEncoder().encode(["beads": SYSSyncedSettings.Entry(value: value, stamp: stamp)])
    }

    func testAValueIsSavedAndComesBack() {
        let first = settings()
        first.set(54, for: "beads")
        XCTAssertEqual(settings().int("beads"), 54)
        XCTAssertEqual(settings()["beads"], "54")
    }

    func testAMissingValueIsNil() {
        XCTAssertNil(settings()["beads"])
        XCTAssertNil(settings().int("beads"))
    }

    func testANewerValueFromTheOtherDeviceWins() throws {
        let local = settings()
        local.set(108, for: "beads")
        local.receive(try payload("27", at: clock.addingTimeInterval(10)))
        XCTAssertEqual(local.int("beads"), 27)
    }

    func testAnOlderValueFromTheOtherDeviceIsIgnored() throws {
        let local = settings()
        local.set(108, for: "beads")
        local.receive(try payload("27", at: clock.addingTimeInterval(-10)))
        XCTAssertEqual(local.int("beads"), 108)
    }

    func testAResetForgetsTheSettings() async throws {
        let local = settings()
        local.set(54, for: "beads")
        suite.removePersistentDomain(forName: suiteName)
        NotificationCenter.default.post(name: .sysDidReset, object: nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(local.int("beads"))
    }

    func testEachSettingIsDecidedOnItsOwn() throws {
        let local = settings()
        local.set(108, for: "beads")
        local.set("om", for: "mantra")
        local.receive(try payload("27", at: clock.addingTimeInterval(10)))
        XCTAssertEqual(local.int("beads"), 27)
        XCTAssertEqual(local["mantra"], "om")
    }
}
