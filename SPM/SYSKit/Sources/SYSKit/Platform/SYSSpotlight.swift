#if canImport(CoreSpotlight) && !os(watchOS)
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// One thing worth finding in system search.
public struct SYSSpotlightItem {
    public let id: String
    public let title: String
    public let contentDescription: String?
    public let keywords: [String]
    public let url: URL?
    let thumbnailData: Data?
    let createdAt: Date?
    let modifiedAt: Date?
    let contentType: UTType

    public init(id: String, title: String, contentDescription: String? = nil,
                keywords: [String] = [], url: URL? = nil,
                thumbnailData: Data? = nil, createdAt: Date? = nil, modifiedAt: Date? = nil,
                contentType: UTType = .text) {
        self.id = id
        self.title = title
        self.contentDescription = contentDescription
        self.keywords = keywords
        self.url = url
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contentType = contentType
    }
}

/// Tracks which ids are currently indexed under one domain, so a sync can tell "still valid" apart from "indexed but sho...
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

@MainActor
/// Indexing for Spotlight search, and the one tap-identifier scheme every app now shares instead of each writing its own.
public enum SYSSpotlight {
    public static func makeIdentifier(kind: String, id: String) -> String {
        "\(kind)-\(id)"
    }

    public static func parseIdentifier(_ raw: String) -> (kind: String, id: String)? {
        guard let separator = raw.firstIndex(of: "-") else { return nil }
        let kind = String(raw[raw.startIndex..<separator])
        let id = String(raw[raw.index(after: separator)...])
        guard !kind.isEmpty, !id.isEmpty else { return nil }
        return (kind, id)
    }

    public static func index(_ items: [SYSSpotlightItem], domain: String,
                              completion: (@Sendable (Error?) -> Void)? = nil) {
        let searchableItems = items.map { item -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: item.contentType)
            attributes.title = item.title
            attributes.displayName = item.title
            attributes.contentDescription = item.contentDescription
            if !item.keywords.isEmpty { attributes.keywords = item.keywords }
            attributes.url = item.url
            attributes.thumbnailData = item.thumbnailData
            attributes.contentCreationDate = item.createdAt
            attributes.contentModificationDate = item.modifiedAt
            return CSSearchableItem(uniqueIdentifier: item.id, domainIdentifier: domain, attributeSet: attributes)
        }
        CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
            if let error { SYSLogger.error("spotlight: index failed for domain \(domain)", error) }
            completion?(error)
        }
    }

    public static func deindex(ids: [String], completion: (@Sendable (Error?) -> Void)? = nil) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { error in
            if let error { SYSLogger.error("spotlight: deindex failed", error) }
            completion?(error)
        }
    }

    public static func deindexAll(domain: String, completion: (@Sendable (Error?) -> Void)? = nil) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
            if let error { SYSLogger.error("spotlight: deindexAll failed for domain \(domain)", error) }
            completion?(error)
        }
    }

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
