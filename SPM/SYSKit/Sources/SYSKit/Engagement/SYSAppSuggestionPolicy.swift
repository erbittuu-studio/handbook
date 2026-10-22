import Foundation

/// When the "another app you may like" popup may appear, and which app it shows. Pure rules, so they can be tested.
enum SYSAppSuggestionPolicy {
    static let firstOpen = 5
    static let gaps = [3, 4, 5, 6, 7]
    static let laterGap = 10
    static let minimumDays: TimeInterval = 86_400
    static let awayForAnOpen: TimeInterval = 60
    static let remindDelay: TimeInterval = 2 * 86_400
    static let reviewQuiet: TimeInterval = 90

    /// The open on which the popup is next due after it was shown on `opens`: the 5th, then the 8th, 12th, 17th, 23rd, 30th, then every 10th.
    static func nextOpen(after opens: Int, shownCount: Int) -> Int {
        opens + (gaps.indices.contains(shownCount - 1) ? gaps[shownCount - 1] : laterGap)
    }

    /// Due once its open has come (a slot another prompt took is not lost), at least a day after the last popup,
    /// or when a Remind me later day has come.
    static func isDue(opens: Int, nextOpen: Int, lastShown: Date?, remindAfter: Date?, now: Date) -> Bool {
        if let remindAfter { return now >= remindAfter }
        guard opens >= nextOpen else { return false }
        guard let lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= minimumDays
    }

    /// The system review prompt cannot be seen from here, so for a while after one was requested nothing else is shown.
    static func reviewMayBeOpen(lastRequest: Date?, now: Date) -> Bool {
        guard let lastRequest else { return false }
        return now.timeIntervalSince(lastRequest) < reviewQuiet
    }

    /// The app to show next. Apps already opened are skipped, and every app is shown once before one comes round again.
    /// Order: the app's own recommendation list first, then apps in the same category, then the catalog's order.
    static func next(
        from apps: [SYSAppCatalogEntry],
        seen: [String],
        opened: [String],
        recommends: [String] = [],
        category: String? = nil
    ) -> (app: SYSAppCatalogEntry, seen: [String])? {
        let candidates = apps.filter { !opened.contains($0.id) }
        guard !candidates.isEmpty else { return nil }
        var round = seen.filter { id in candidates.contains { $0.id == id } }
        var fresh = candidates.filter { !round.contains($0.id) }
        if fresh.isEmpty {
            round = []
            fresh = candidates
        }
        let ranked = fresh.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element, recommends: recommends, category: category)
            let right = rank(rhs.element, recommends: recommends, category: category)
            return left == right ? lhs.offset < rhs.offset : left < right
        }
        guard let app = ranked.first?.element else { return nil }
        return (app, round + [app.id])
    }

    static func notInstalled(_ apps: [SYSAppCatalogEntry], isInstalled: (SYSAppCatalogEntry) -> Bool) -> [SYSAppCatalogEntry] {
        apps.filter { !isInstalled($0) }
    }

    static func hasAnother(apps: [SYSAppCatalogEntry], opened: [String]) -> Bool {
        apps.filter { !opened.contains($0.id) }.count > 1
    }

    private static func rank(_ app: SYSAppCatalogEntry, recommends: [String], category: String?) -> Int {
        if let place = recommends.firstIndex(of: app.id) { return place }
        let sameCategory = category != nil && app.category == category
        return recommends.count + (sameCategory ? 0 : 1)
    }
}
