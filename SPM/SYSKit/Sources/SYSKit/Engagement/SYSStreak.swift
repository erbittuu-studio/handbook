import Foundation

@MainActor
/// Tracks a daily streak — "5 days in a row": today extends yesterday's streak, a gap resets it to 1, and recording twic...
public final class SYSStreak {
    private let countKey: SYSSettingsKey<Int>
    private let lastDateKey: SYSSettingsKey<Date?>
    private let calendar: Calendar
    private let now: () -> Date

    public init(
        countKey: SYSSettingsKey<Int>,
        lastDateKey: SYSSettingsKey<Date?>,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.countKey = countKey
        self.lastDateKey = lastDateKey
        self.calendar = calendar
        self.now = now
    }

    public var count: Int { SYSSettings.shared[countKey] }

    private var lastDate: Date? { SYSSettings.shared[lastDateKey] }

    public var isActive: Bool {
        guard let last = lastDate else { return false }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: now())
        ).day ?? .max
        return days <= 1
    }

    @discardableResult
    public func recordToday() -> Int {
        let today = calendar.startOfDay(for: now())

        if let last = lastDate {
            let lastDay = calendar.startOfDay(for: last)
            guard lastDay != today else { return count }
            let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            SYSSettings.shared[countKey] = gap == 1 ? count + 1 : 1
        } else {
            SYSSettings.shared[countKey] = 1
        }

        SYSSettings.shared[lastDateKey] = now()
        return count
    }
}
