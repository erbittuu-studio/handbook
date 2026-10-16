#if canImport(CoreSpotlight) && !os(watchOS)
import CoreSpotlight
import Foundation

/// One thing worth finding in system search: plain values only, so it can cross threads, with a picture named by file and not loaded.
public struct SYSSearchEntry: Sendable, Equatable {
    public let id: String
    public let title: String
    public let summary: String?
    public let keywords: [String]
    public let thumbnail: Picture?
    public let thumbnailMode: SYSSearchThumbnail.Mode

    /// The picture for a result: a file, bytes the app already made, or bytes it makes only when the result is new or changed, each named by a key that changes with the picture.
    public enum Picture: Sendable, Equatable {
        case file(URL)
        case image(key: String, data: Data)
        case render(key: String, make: @Sendable () async -> Data?)

        var signature: String {
            switch self {
            case let .file(url): return url.lastPathComponent
            case let .image(key, _), let .render(key, _): return key
            }
        }

        public static func == (lhs: Picture, rhs: Picture) -> Bool {
            lhs.signature == rhs.signature
        }

        func jpeg(mode: SYSSearchThumbnail.Mode) async -> Data? {
            switch self {
            case let .file(url): return SYSSearchThumbnail.jpeg(contentsOf: url, mode: mode)
            case let .image(_, data): return SYSSearchThumbnail.jpeg(from: data, mode: mode)
            case let .render(_, make): return await make().flatMap { SYSSearchThumbnail.jpeg(from: $0, mode: mode) }
            }
        }
    }

    public init(
        id: String,
        title: String,
        summary: String? = nil,
        keywords: [String] = [],
        thumbnail: Picture? = nil,
        thumbnailMode: SYSSearchThumbnail.Mode = .fill
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.thumbnail = thumbnail
        self.thumbnailMode = thumbnailMode
    }

    func signature(adding hosted: [String]) -> String {
        [
            title,
            summary ?? "",
            hosted.joined(separator: ","),
            keywords.joined(separator: ","),
            thumbnail?.signature ?? "",
            thumbnailMode.rawValue
        ].joined(separator: "|")
    }

    func searchKeywords(adding hosted: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return ([title] + hosted + keywords)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

/// Keeps system search in step with an app's content, on a background actor: it indexes what changed, removes what went away, and clears results an older version left behind.
public actor SYSSearchIndexer {
    public static let shared = SYSSearchIndexer()

    private static let schema = 1
    private static let batchSize = 40
    private static let maxKeywords = 30

    private let settings: SYSSettings
    private let domainPrefix: String
    private var generations: [String: Int] = [:]
    private var clearing: Task<Bool, Never>?
    private var builders: [String: @Sendable () async -> [SYSSearchEntry]] = [:]

    init(settings: SYSSettings = .shared, bundle: Bundle = .main) {
        self.settings = settings
        domainPrefix = "\(bundle.bundleIdentifier ?? "app").search"
    }

    public func replace(kind: String, build: @escaping @Sendable () async -> [SYSSearchEntry]) async {
        let generation = (generations[kind] ?? 0) + 1
        generations[kind] = generation
        builders[kind] = build
        await clearIfNeeded()
        guard generations[kind] == generation else { return }
        SYSLogger.info("search: \(kind) started")

        let hosted = SYSConfig.shared.data.search?.keywords ?? []
        var current: [String: SYSSearchEntry] = [:]
        for entry in await build() {
            current[SYSSpotlight.makeIdentifier(kind: kind, id: entry.id)] = entry
        }

        let key = signatureKey(kind)
        let known = settings.value(for: key) ?? [:]
        let stale = known.keys.filter { current[$0] == nil }
        if !stale.isEmpty { SYSSpotlight.deindex(ids: Array(stale)) }

        let changed = current
            .filter { known[$0.key] != $0.value.signature(adding: hosted) }
            .sorted { $0.key < $1.key }
        for start in stride(from: 0, to: changed.count, by: Self.batchSize) {
            let batch = changed[start..<min(start + Self.batchSize, changed.count)]
            var items: [SYSSpotlightItem] = []
            for (identifier, entry) in batch {
                items.append(await item(identifier: identifier, kind: kind, entry: entry, hosted: hosted))
            }
            if await SYSSpotlight.indexAndWait(items, domain: domain(kind)) != nil { return }
            guard generations[kind] == generation else { return }
        }
        settings.set(current.mapValues { $0.signature(adding: hosted) }, for: key)
        SYSLogger.info("search: \(kind) indexed \(changed.count) of \(current.count), removed \(stale.count)")
    }

    public func refresh() async {
        for (kind, build) in builders {
            await replace(kind: kind, build: build)
        }
    }

    public func forget(kind: String) async {
        generations[kind, default: 0] += 1
        builders[kind] = nil
        settings.set(nil, for: signatureKey(kind))
        await SYSSpotlight.deindexAllAndWait(domain: domain(kind))
    }

    private func clearIfNeeded() async {
        let flag = SYSSettingsKey<Bool>("sys_search_cleared_v\(Self.schema)", default: false)
        guard !settings[flag] else { return }
        if let clearing {
            _ = await clearing.value
            return
        }
        let task = Task { await SYSSpotlight.deleteEverything() }
        clearing = task
        if await task.value { settings[flag] = true }
        clearing = nil
    }

    private func item(identifier: String, kind: String, entry: SYSSearchEntry, hosted: [String]) async -> SYSSpotlightItem {
        let path = entry.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.id
        return SYSSpotlightItem(
            id: identifier,
            title: entry.title,
            contentDescription: entry.summary,
            keywords: entry.searchKeywords(adding: hosted, limit: Self.maxKeywords),
            url: SYSDeepLink.url(host: kind, path: path),
            thumbnailData: await entry.thumbnail?.jpeg(mode: entry.thumbnailMode)
        )
    }

    private func domain(_ kind: String) -> String { "\(domainPrefix).\(kind)" }

    private func signatureKey(_ kind: String) -> SYSSettingsKey<[String: String]?> {
        SYSSettingsKey<[String: String]?>("sys_search_signatures_v\(Self.schema)_\(kind)", default: nil)
    }
}
#endif
