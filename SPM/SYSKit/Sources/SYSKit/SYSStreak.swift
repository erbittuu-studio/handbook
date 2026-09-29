import Foundation

/// Tracks a daily streak — "5 days in a row": today extends yesterday's
/// streak, a gap resets it to 1, and recording twice in the same day does
/// nothing. Calendar-day boundaries, not a rolling 24 hours, so a session
/// at 11pm and another at 7am the next morning are two different days even
/// eight hours apart — the same day-boundary math every app that wants a
/// streak was going to need, and easy to get subtly wrong (timezone, DST,
/// "yesterday" computed as `now - 86400`) if each one wrote it separately.
///
/// Knows nothing about what the streak is *for* — an app names its own
/// keys and decides what "did the thing today" means; this only knows
/// about days.
@MainActor
public final class SYSStreak {
    private let countKey: SYSSettingsKey<Int>
    private let lastDateKey: SYSSettingsKey<Date?>
    private let calendar: Calendar
    private let now: () -> Date

    /// - Parameters:
    ///   - countKey/lastDateKey: this streak's own keys — an app tracking
    ///     more than one streak (say, "days used" and "days perfect score")
    ///     gives each its own pair.
    ///   - now: real code never passes this; tests inject a fixed clock so
    ///     "the next day" doesn't mean actually waiting a day.
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

    /// Whether the streak is still alive — today or yesterday, not further
    /// back. A display that only shows the count when this is true avoids
    /// showing "🔥 5" days after the streak actually broke.
    public var isActive: Bool {
        guard let last = lastDate else { return false }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: now())
        ).day ?? .max
        return days <= 1
    }

    /// Call once per "did the thing today" event. Returns the count after
    /// recording, so a caller can show it immediately without a second
    /// read. Safe to call more than once in the same calendar day — only
    /// the first call that day changes anything.
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
