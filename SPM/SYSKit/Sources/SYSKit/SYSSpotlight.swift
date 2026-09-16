#if canImport(CoreSpotlight) && !os(watchOS)
import CoreSpotlight
import Foundation

/// One thing worth finding in system search.
public struct SYSSpotlightItem {
    public let id: String
    public let title: String
    public let contentDescription: String?
    public let keywords: [String]
    public let url: URL?

    public init(id: String, title: String, contentDescription: String? = nil,
                keywords: [String] = [], url: URL? = nil) {
        self.id = id
        self.title = title
        self.contentDescription = contentDescription
        self.keywords = keywords
        self.url = url
    }
}

/// Tracks which ids are currently indexed under one domain, so a sync can
/// tell "still valid" apart from "indexed but shouldn't be anymore".
///
/// Backed by a plain `SYSSettingsKey<[String]?>` — the Codable/JSON path, not
/// a native plist array. That is only safe for a key nothing has written to
/// yet: an app with an *existing* native-array key for this purpose (one was
/// found during this work) keeps it on raw `UserDefaults`, because reading a
/// native array back through the Codable path returns nil and looks like
/// "nothing indexed" to every install that upgrades. A tracker constructed
/// here is always a new key, so that risk does not apply to it.
public final class SYSIndexedIDTracker {
    private let key: SYSSettingsKey<[String]?>

    public init(domain: String) {
        key = SYSSettingsKey<[String]?>("sys_spotlight_indexed_\(domain)", default: nil)
    }

    public var ids: Set<String> {
        Set(SYSSettings.shared.value(for: key) ?? [])
    }

    public func setIDs(_ ids: Set<String>) {
        SYSSettings.shared.set(Array(ids), for: key)
    }
}

/// Indexing for Spotlight search, and the one tap-identifier scheme every app
/// now shares instead of each writing its own.
///
/// `CSSearchableIndex` itself is already a thin API — the actual repeated
/// code was building the attribute set the same way three times, hand-rolling
/// a stale-item sync, and each app inventing its own identifier shape for the
/// tap handler to parse back out. All three are here once.
@MainActor
public enum SYSSpotlight {
    /// `"<kind>-<id>"` — e.g. `makeIdentifier(kind: "pack", id: "42")` →
    /// `"pack-42"`. `kind` must not itself contain `-`; `id` may.
    public static func makeIdentifier(kind: String, id: String) -> String {
        "\(kind)-\(id)"
    }

    /// The inverse of `makeIdentifier`. Splits on the first `-` only, so an id
    /// containing `-` round-trips.
    public static func parseIdentifier(_ raw: String) -> (kind: String, id: String)? {
        guard let separator = raw.firstIndex(of: "-") else { return nil }
        let kind = String(raw[raw.startIndex..<separator])
        let id = String(raw[raw.index(after: separator)...])
        guard !kind.isEmpty, !id.isEmpty else { return nil }
        return (kind, id)
    }

    public static func index(_ items: [SYSSpotlightItem], domain: String,
                              completion: ((Error?) -> Void)? = nil) {
        let searchableItems = items.map { item -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = item.title
            attributes.contentDescription = item.contentDescription
            if !item.keywords.isEmpty { attributes.keywords = item.keywords }
            attributes.url = item.url
            return CSSearchableItem(uniqueIdentifier: item.id, domainIdentifier: domain, attributeSet: attributes)
        }
        CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
            if let error { SYSLogger.error("spotlight: index failed for domain \(domain)", error) }
            completion?(error)
        }
    }

    public static func deindex(ids: [String], completion: ((Error?) -> Void)? = nil) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { error in
            if let error { SYSLogger.error("spotlight: deindex failed", error) }
            completion?(error)
        }
    }

    public static func deindexAll(domain: String, completion: ((Error?) -> Void)? = nil) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
            if let error { SYSLogger.error("spotlight: deindexAll failed for domain \(domain)", error) }
            completion?(error)
        }
    }

    /// Deindexes whatever `tracker` last recorded that isn't in
    /// `shouldBeIndexed` anymore, records the new full set, and returns the
    /// ids that are newly valid and still need indexing — the caller already
    /// has the source objects for those, so this hands back ids to build
    /// `SYSSpotlightItem`s for, not items itself.
    ///
    /// `shouldBeIndexed` and the tracked set are both full Spotlight
    /// identifiers (`makeIdentifier` output), not raw content ids — that is
    /// what `deindex(ids:)` takes, so no reconstruction happens in here.
    @discardableResult
    public static func sync(shouldBeIndexed: Set<String>,
                             tracker: SYSIndexedIDTracker) -> Set<String> {
        let previouslyIndexed = tracker.ids
        let stale = previouslyIndexed.subtracting(shouldBeIndexed)
        if !stale.isEmpty {
            deindex(ids: Array(stale))
        }
        tracker.setIDs(shouldBeIndexed)
        return shouldBeIndexed.subtracting(previouslyIndexed)
    }
}
#endif
