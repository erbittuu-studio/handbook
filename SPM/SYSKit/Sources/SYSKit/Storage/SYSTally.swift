import Foundation

/// A count that can go up and down on several devices and still merge without losing a tap: each device keeps its own ups and downs and the largest seen per device wins.
public struct SYSCounter: Codable, Equatable, Sendable {
    public private(set) var up: [String: Int] = [:]
    public private(set) var down: [String: Int] = [:]

    public init() {}

    public var value: Int {
        up.values.reduce(0, +) - down.values.reduce(0, +)
    }

    public mutating func add(_ amount: Int, device: String) {
        if amount >= 0 {
            up[device, default: 0] += amount
        } else {
            down[device, default: 0] -= amount
        }
    }

    public mutating func merge(_ other: SYSCounter) {
        for (device, count) in other.up { up[device] = max(up[device] ?? 0, count) }
        for (device, count) in other.down { down[device] = max(down[device] ?? 0, count) }
    }
}

/// Counts per item for all time and per day, such as beads chanted per mantra, built from counters so two devices can merge.
public struct SYSTally: Codable, Equatable, Sendable {
    public static let keptDays = 120

    public private(set) var totals: [String: SYSCounter] = [:]
    public private(set) var days: [String: [String: SYSCounter]] = [:]

    public init() {}

    public func total(of item: String) -> Int {
        max(0, totals[item]?.value ?? 0)
    }

    public func count(on day: String) -> Int {
        max(0, (days[day] ?? [:]).values.reduce(0) { $0 + $1.value })
    }

    public func count(of item: String, on day: String) -> Int {
        max(0, days[day]?[item]?.value ?? 0)
    }

    public mutating func add(_ amount: Int, to item: String, on day: String, device: String) {
        guard amount != 0 else { return }
        totals[item, default: SYSCounter()].add(amount, device: device)
        days[day, default: [:]][item, default: SYSCounter()].add(amount, device: device)
        trim(keeping: day)
    }

    public mutating func setTotal(of item: String, to value: Int, on day: String, device: String) {
        add(max(0, value) - total(of: item), to: item, on: day, device: device)
    }

    public mutating func merge(_ other: SYSTally, today: String) {
        for (item, counter) in other.totals { totals[item, default: SYSCounter()].merge(counter) }
        for (day, items) in other.days {
            for (item, counter) in items { days[day, default: [:]][item, default: SYSCounter()].merge(counter) }
        }
        trim(keeping: today)
    }

    public func streak(today: Date, calendar: Calendar = .current) -> Int {
        var day = today
        if count(on: Self.dayKey(day, calendar: calendar)) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var length = 0
        while count(on: Self.dayKey(day, calendar: calendar)) > 0 {
            length += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return length
    }

    public func recent(_ length: Int, endingOn today: Date, calendar: Calendar = .current) -> [(day: String, count: Int)] {
        (0..<length).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map {
                let key = Self.dayKey($0, calendar: calendar)
                return (key, count(on: key))
            }
        }
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private mutating func trim(keeping today: String) {
        guard days.count > Self.keptDays else { return }
        let newest = days.keys.filter { $0 <= today }.sorted().suffix(Self.keptDays)
        let keep = Set(newest).union(days.keys.filter { $0 > today })
        days = days.filter { keep.contains($0.key) }
    }
}
