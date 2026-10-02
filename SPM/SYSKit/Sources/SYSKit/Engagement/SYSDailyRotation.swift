import Foundation

/// Picks one item per calendar day from a list, walking through it in order and starting over when it runs out, so
/// "today's prayer" is the same all day, different tomorrow, and never random. Day 1 of the year is the first item.
public enum SYSDailyRotation {
    public static func pick<Item>(_ items: [Item], on date: Date = Date(), calendar: Calendar = .current) -> Item? {
        guard !items.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return items[(day - 1) % items.count]
    }
}
