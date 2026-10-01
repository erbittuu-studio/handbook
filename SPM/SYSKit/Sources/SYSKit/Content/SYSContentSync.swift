import Foundation

/// One content item a manifest lists — the handful of fields the generic
/// sync loop actually touches. Everything else about an app's item (name,
/// description, tags, whatever) stays in the app's own type; SYSKit never
/// invents a manifest shape.
public protocol SYSContentItem: Codable, Identifiable, SYSPublishable where ID == String {
    /// Hosting-relative path to this item's downloadable bundle.
    var bundle: String { get }
    var checksum: String? { get }
}

public enum SYSContentItemStatus: Equatable, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case failed
}

public enum SYSContentSyncState: Equatable, Sendable {
    case idle
    case downloading(completed: Int, total: Int)
    case ready
    case failed(itemIds: [String])
    /// `refresh()` could not get the manifest at all, and nothing usable is
    /// cached from an earlier run — distinct from `.failed`, which means the
    /// manifest arrived but some items didn't.
    case manifestUnavailable

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public enum SYSContentSyncError: Error {
    case invalidBundleURL(itemId: String)
    case downloadFailed(itemId: String)
    case checksumMismatch(itemId: String)
    case installFailed(itemId: String)
}

/// Generic on-disk cache + downloader for a manifest's items: the
/// live/staging/backup/downloads layout, checksum tracking, atomic
/// install-with-backup, download-what's-missing loop and stale-item cleanup
/// that were hand-rolled, slightly differently, in every app. An app hands
/// this its item type and a base URL; everything past that — what's on
/// disk, what's downloading, what failed — lives here.
///
/// Unpacking is included, not delegated — `SYSZip` reads the archive itself
/// (see that file), so an app conforms its item type to `SYSContentItem`,
/// configures a base URL and calls `sync`. Nothing else is app-side.
@MainActor
public final class SYSContentSync<Item: SYSContentItem>: ObservableObject {

    @Published public private(set) var items: [Item] = []
    @Published public private(set) var itemStates: [String: SYSContentItemStatus] = [:]
    @Published public private(set) var syncState: SYSContentSyncState = .idle

    private let fm = FileManager.default
    private let storageFolder: String
    private let dataVersionKey: SYSSettingsKey<Int>
    private let itemChecksumMapKey: SYSSettingsKey<[String: String]>
    /// Same seam `SYSConfig`/`SYSAppCatalog` use: real code never passes
    /// this (it defaults to `.main`, where `SYSContentID` actually lives),
    /// tests inject a stub so the decrypt key is something they control.
    private let bundle: Bundle

    /// The manifest this instance owns — `config.json`'s `manifests` list
    /// names it, and it lives entirely under its own folder:
    /// `<content root>/<manifestName>/manifest.json` + `.../packs/`. An app
    /// with more than one manifest (Prarthana: `content`, `festivals`) has
    /// one `SYSContentSync` per name, each independent.
    public let manifestName: String

    private var explicitBaseURL: String?
    private var manifestETag: String?
    /// `ensure(_:)` calls already running, keyed by item id — two taps on
    /// the same not-yet-downloaded item, or a screen calling `ensure` while
    /// startup's own eager sync is still fetching that same item, must not
    /// download the same bytes twice. Same reasoning as `SYSAssets`'
    /// `inFlight`.
    private var inFlightEnsures: [String: Task<Result<Void, SYSContentSyncError>, Never>] = [:]

    /// - Parameters:
    ///   - manifestName: which of this app's manifests this instance owns.
    ///   - storageFolder: on-disk folder name under Application Support.
    ///   - dataVersionKey: pass the app's existing key if migrating from a
    ///     hand-rolled cache — the same key name is what makes existing
    ///     installs recognize what they already downloaded.
    ///   - itemChecksumMapKey: same migration note as `dataVersionKey`.
    public init(
        manifestName: String,
        storageFolder: String,
        dataVersionKey: SYSSettingsKey<Int>,
        itemChecksumMapKey: SYSSettingsKey<[String: String]>,
        bundle: Bundle = .main
    ) {
        self.manifestName = manifestName
        self.storageFolder = storageFolder
        self.dataVersionKey = dataVersionKey
        self.itemChecksumMapKey = itemChecksumMapKey
        self.bundle = bundle
        createDirectoriesIfNeeded()
    }

    // MARK: - Configuration

    /// Only needed for a custom domain, a staging site, or a test double —
    /// otherwise this manifest's root is derived automatically from
    /// `SYSHosting.contentURL()` + `manifestName`.
    public func configure(baseURL: String) {
        self.explicitBaseURL = baseURL
    }

    /// This manifest's own root — `<content root>/<manifestName>/` unless
    /// `configure(baseURL:)` overrode it.
    public var baseURL: String {
        if let explicitBaseURL { return explicitBaseURL }
        guard let root = SYSHosting.contentURL(bundle: bundle) else { return "" }
        return root.appendingPathComponent(manifestName, isDirectory: true).absoluteString
    }

    /// A URL into this manifest's own hosting root — for a served asset
    /// that isn't one of the per-item downloads `fileURL`/`loadFile` cover
    /// (a category's or festival's own image, say, named by a manifest
    /// field rather than living inside an item's own folder).
    public func url(path: String) -> URL? {
        // `URL(string:)` happily builds a schemeless "/manifest.json" from an
        // empty base — not nil, so an unconfigured instance would otherwise
        // attempt a real request to a meaningless URL instead of failing
        // closed the way `.notConfigured` promises.
        guard !baseURL.isEmpty else { return nil }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(baseURL)/\(relative)")
    }

    // MARK: - Paths
    //
    // Not public — none of this app's business. `loadFile`/`fileURL`/
    // `filenames`/`loadItemIndex` are the read surface; where things
    // actually live on disk can change without that ever being a breaking
    // change for a caller.

    private var applicationSupportURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    var rootURL: URL { applicationSupportURL.appendingPathComponent(storageFolder) }
    var liveRoot: URL { rootURL.appendingPathComponent("live") }
    var backupRoot: URL { rootURL.appendingPathComponent("backup") }
    var workingRoot: URL { rootURL.appendingPathComponent("downloads") }
    var itemsRoot: URL { liveRoot.appendingPathComponent("items") }
    var liveManifestURL: URL { liveRoot.appendingPathComponent("manifest.json") }
    /// Where `ensureBundle` caches a companion asset (Prarthana's per-item
    /// audio) — beside `items`, not inside it, since it isn't itself an
    /// item's install.
    var bundlesRoot: URL { liveRoot.appendingPathComponent("bundles") }

    private func createDirectoriesIfNeeded() {
        for dir in [rootURL, liveRoot, backupRoot, workingRoot, itemsRoot, bundlesRoot]
        where !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Everything under here came from the server and can come again —
        // backing it up would put a copy of the app's content in iCloud for
        // every install, to save a download the app is willing to do
        // anyway. Excluding the root covers every subfolder; setting it
        // once at creation is enough, it isn't a per-file attribute that a
        // later download could lose.
        var root = rootURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    // MARK: - Version / checksum tracking
    //
    // Not public — the schema-version bookkeeping that decides whether a
    // manifest bump means "wipe and start over" (see `sync`). No app reads
    // or sets this directly.

    var dataVersion: Int {
        get { SYSSettings.shared[dataVersionKey] }
        set { SYSSettings.shared[dataVersionKey] = newValue }
    }

    private var itemChecksumMap: [String: String] {
        get { SYSSettings.shared[itemChecksumMapKey] }
        set { SYSSettings.shared[itemChecksumMapKey] = newValue }
    }

    private func saveItemChecksum(_ checksum: String, for itemId: String) {
        var map = itemChecksumMap
        map[itemId] = checksum
        itemChecksumMap = map
    }

    private func isItemAvailable(id: String, checksum: String?) -> Bool {
        guard itemExists(id: id) else { return false }
        guard let checksum else { return true }
        return itemChecksumMap[id] == checksum
    }

    private func itemExists(id: String) -> Bool {
        fm.fileExists(atPath: itemIndexURL(id: id).path)
    }

    private func itemFolderURL(id: String) -> URL { itemsRoot.appendingPathComponent(id) }
    private func itemIndexURL(id: String) -> URL { itemFolderURL(id: id).appendingPathComponent("index.json") }

    // MARK: - Manifest passthrough

    public func loadLocalManifest<T: Decodable>(as type: T.Type) -> T? {
        guard fm.fileExists(atPath: liveManifestURL.path),
              let data = try? Data(contentsOf: liveManifestURL) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func saveManifest<T: Encodable>(_ manifest: T) throws {
        let dir = liveManifestURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try JSONEncoder().encode(manifest).write(to: liveManifestURL, options: .atomic)
    }

    /// The last-fetched manifest, decoded into the app's own fuller type —
    /// for whatever extra top-level fields it has (`groups`, `categories`,
    /// `deities`, whatever) that `SYSContentItem` doesn't need to know
    /// about. Same file `refresh()` already fetched; nothing new to fetch.
    public func manifest<T: Decodable>(as type: T.Type) -> T? {
        loadLocalManifest(as: type)
    }

    /// The shape `refresh()` needs to drive downloads — `manifestVersion`
    /// and `items`, nothing else. An app's fuller manifest type (read back
    /// via `manifest(as:)`) can carry as many extra top-level fields as it
    /// likes; this never has to know about them.
    private struct MinimalManifest: Decodable {
        let manifestVersion: Int
        let items: [Item]
    }

    /// Why the last `refresh()` couldn't get a usable manifest — nil once one
    /// has. `prepareRequired` reads this for `SYSBootstrap`; a screen that
    /// only watches `syncState` never needs it.
    public private(set) var lastManifestError: SYSContentError?

    // MARK: - Refresh

    /// Fetches this manifest and updates `items`/`itemStates`/`syncState`.
    /// Safe to call anytime — already-current content costs one small
    /// request (an ETag 304) and nothing else.
    ///
    /// - Parameter downloadAll: true (the default) eagerly downloads every
    ///   item, decrypted and cached, right away — right for a manifest whose
    ///   content is small enough or central enough to want on every device
    ///   (Colorful's worlds, Prarthana's prayers). false only fetches and
    ///   indexes the manifest itself; items are fetched one at a time with
    ///   `ensure(_:)` instead — right for a manifest with many packs nobody
    ///   opens most of (Drawing's doodle/stamp categories, all `required:
    ///   false`). Either way every item still ends up in `items`/
    ///   `itemStates`, just downloaded or not.
    ///
    /// A failed fetch falls back to whatever manifest is already cached on
    /// disk, so a network hiccup on a fully-populated install never looks
    /// like a failure — only a first launch with nothing cached yet can end
    /// up at `.manifestUnavailable`.
    public func refresh(
        downloadAll: Bool = true,
        progress: SYSAssetProgressHandler? = nil
    ) async {
        guard let manifestURL = url(path: "manifest.json") else {
            lastManifestError = .notConfigured
            syncState = useCachedManifestIfAny() ? .ready : .manifestUnavailable
            return
        }

        do {
            let (data, etag) = try await SYSNetwork.shared.data(manifestURL, etag: manifestETag)
            guard let decoded = try? JSONDecoder().decode(MinimalManifest.self, from: data) else {
                lastManifestError = .unreadableManifest(manifestName)
                syncState = useCachedManifestIfAny() ? .ready : .manifestUnavailable
                return
            }
            manifestETag = etag
            persistRawManifest(data)
            lastManifestError = nil
            let visible = SYSPublishing.visible(decoded.items)
            if downloadAll {
                await sync(items: visible, dataVersion: decoded.manifestVersion, progress: progress)
            } else {
                loadCached(visible)
                self.dataVersion = decoded.manifestVersion
                syncState = .ready
            }
        } catch SYSNetworkError.notModified {
            guard useCachedManifestIfAny() else {
                syncState = .manifestUnavailable
                return
            }
            // A 304 says the manifest is unchanged, not that every pack in it
            // is on disk: a first `refresh(downloadAll: false)` in this same
            // process stored the ETag, so the `downloadAll: true` call that
            // follows lands here having downloaded nothing. Still owed.
            if downloadAll, let cached = loadLocalManifest(as: MinimalManifest.self) {
                await downloadMissing(
                    items: SYSPublishing.visible(cached.items),
                    dataVersion: cached.manifestVersion,
                    progress: progress
                )
            } else {
                syncState = .ready
            }
        } catch {
            SYSLogger.debug("contentSync[\(manifestName)]: manifest fetch failed, using the held copy if any — \(error)")
            lastManifestError = Self.contentError(for: error)
            syncState = useCachedManifestIfAny() ? .ready : .manifestUnavailable
        }
    }

    /// Populates `items`/`itemStates` from whatever manifest is already on
    /// disk, without a network call. Used when a fetch fails or is skipped
    /// (304) — the same "carry on with what's held" rule `SYSConfig` and
    /// `SYSAssets` both follow.
    @discardableResult
    private func useCachedManifestIfAny() -> Bool {
        guard let cached = loadLocalManifest(as: MinimalManifest.self) else { return false }
        loadCached(SYSPublishing.visible(cached.items))
        return true
    }

    private static func contentError(for error: Error) -> SYSContentError {
        switch error {
        case SYSNetworkError.offline: return .offline
        case let SYSNetworkError.http(status): return .server(status: status)
        case let SYSNetworkError.decoding(detail): return .unreadableManifest(detail)
        default: return .offline
        }
    }

    // MARK: - On-demand single item

    /// Downloads one item if it isn't already cached — for a manifest whose
    /// items are fetched as needed rather than all at once (`refresh
    /// (downloadAll: false)`'s counterpart). Safe to call again, and safe to
    /// call concurrently for the same id: a second call while the first is
    /// still running waits on it rather than starting a duplicate download.
    @discardableResult
    public func ensure(_ itemID: String) async -> Result<Void, SYSContentSyncError> {
        if itemStates[itemID] == .downloaded { return .success(()) }
        if let running = inFlightEnsures[itemID] { return await running.value }

        guard let item = items.first(where: { $0.id == itemID }) else {
            return .failure(.invalidBundleURL(itemId: itemID))
        }

        itemStates[itemID] = .downloading
        let task = Task { [weak self] () -> Result<Void, SYSContentSyncError> in
            guard let self else { return .failure(.installFailed(itemId: itemID)) }
            do {
                try await self.downloadAndInstall(item)
                self.itemStates[itemID] = .downloaded
                return .success(())
            } catch let error as SYSContentSyncError {
                self.itemStates[itemID] = .failed
                return .failure(error)
            } catch {
                self.itemStates[itemID] = .failed
                return .failure(.installFailed(itemId: itemID))
            }
        }
        inFlightEnsures[itemID] = task
        let result = await task.value
        inFlightEnsures[itemID] = nil
        return result
    }

    // MARK: - Startup gating

    /// `refresh()`, translated into the currency `SYSBootstrap`/
    /// `SYSStartup` already speak — pass this (or a closure composing
    /// several, for an app with more than one manifest) as `SYSBootstrap
    /// .start`'s `prepareContent`.
    /// Blocks the app (`.dataUnavailable`, the maintenance-style screen)
    /// only when there is truly nothing usable — never for "one pack out of
    /// many failed." A single corrupt upload or one bad network blip must
    /// not lock a device out of content it already has, whether that's
    /// everything-but-one from today's fetch or everything from a previous
    /// launch. `syncState`/`itemStates` still record exactly what failed,
    /// for a screen that wants to say so without blocking on it.
    @discardableResult
    public func prepareRequired(
        progress: SYSAssetProgressHandler? = nil
    ) async -> Result<Void, SYSContentError> {
        await refresh(downloadAll: true, progress: progress)
        if hasCachedContent {
            return .success(())
        }
        switch syncState {
        case let .failed(itemIds):
            return .failure(.corrupt(pack: itemIds.joined(separator: ", ")))
        case .manifestUnavailable:
            return .failure(lastManifestError ?? .offline)
        case .ready, .idle, .downloading:
            // .ready with nothing cached means the manifest legitimately has
            // zero items — not a failure, there is simply nothing to show
            // yet. .idle/.downloading are unreachable after refresh() but
            // not a promise syncState's type can make.
            return .success(())
        }
    }

    /// Raw bytes as fetched, not re-encoded — so an app's fuller manifest
    /// type keeps every field the server sent, including ones this generic
    /// layer never decodes.
    private func persistRawManifest(_ data: Data) {
        let dir = liveManifestURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: liveManifestURL, options: .atomic)
    }

    // MARK: - Loading what's already cached

    /// Populates `items`/`itemStates` from a manifest already on disk (or
    /// bundled in the app) without triggering a network fetch — the app
    /// calls this at launch before deciding whether a fetch is needed.
    public func loadCached(_ items: [Item]) {
        self.items = items
        for item in items {
            itemStates[item.id] = isItemAvailable(id: item.id, checksum: item.checksum) ? .downloaded : .notDownloaded
        }
    }

    /// Same as `loadCached`, but marks every item downloaded outright — for
    /// a bundled fallback manifest, which ships with the app itself.
    public func loadBundled(_ items: [Item]) {
        self.items = items
        for item in items {
            itemStates[item.id] = .downloaded
        }
        syncState = .ready
    }

    public func isAvailable(id: String) -> Bool {
        itemStates[id] == .downloaded
    }

    /// Whether there is anything usable on disk right now, before `sync` has
    /// even been called — the signal a launch screen uses to decide whether
    /// it can move on immediately (a lazy download continuing underneath, a
    /// bug in one item's fetch only ever fails that item, never this flag)
    /// or must wait for `syncState` to reach `.ready` or `.failed` because
    /// nothing is cached yet. Whether to actually wait stays a per-app,
    /// per-screen call — this only answers "is there anything to show".
    public var hasCachedContent: Bool {
        itemStates.values.contains(.downloaded)
    }

    public func meta(for id: String) -> Item? {
        items.first { $0.id == id }
    }

    // MARK: - Sync

    /// Brings disk in line with `items` at `dataVersion`: downloads what's
    /// missing, drops what's no longer listed. Call once per manifest fetch,
    /// after the app has decoded and gated the manifest and filtered it
    /// through `SYSPublishing.visible` — this never sees an unpublished item.
    ///
    /// `progress` is for a caller driving this directly rather than through
    /// `refresh`/`prepareRequired` — a screen that only reads `syncState`
    /// (already `@Published`) never needs it. No byte counts: `SYSContentItem`
    /// doesn't require a size field, so this only ever reports pack counts —
    /// `SYSAssetProgress.fraction` already falls back to those when totals
    /// are 0.
    public func sync(
        items: [Item],
        dataVersion remoteVersion: Int,
        progress: SYSAssetProgressHandler? = nil
    ) async {
        let localVersion = dataVersion
        if localVersion > 0 && remoteVersion != localVersion {
            clearAllData()
        }

        self.items = items
        for item in items {
            itemStates[item.id] = isItemAvailable(id: item.id, checksum: item.checksum) ? .downloaded : .notDownloaded
        }

        removeObsoleteItems(currentItems: items)
        await downloadMissing(items: items, dataVersion: remoteVersion, progress: progress)
    }

    /// How many packs download at once. Sequential leaves a phone idle
    /// between one pack's unzip and the next request; more than a few just
    /// competes with itself for the same connection.
    private static var maxConcurrentDownloads: Int { 3 }

    /// Public so an app that has already indexed the manifest
    /// (`refresh(downloadAll: false)`) can fetch what's missing without a
    /// second manifest request — and without depending on how an ETag
    /// answers it.
    public func downloadMissing(progress: SYSAssetProgressHandler? = nil) async {
        await downloadMissing(items: items, dataVersion: dataVersion, progress: progress)
    }

    private func downloadMissing(
        items: [Item],
        dataVersion: Int,
        progress: SYSAssetProgressHandler?
    ) async {
        let toDownload = items.filter { itemStates[$0.id] != .downloaded }

        guard !toDownload.isEmpty else {
            syncState = .ready
            self.dataVersion = dataVersion
            return
        }

        let total = toDownload.count
        var completed = 0
        var failed: [String] = []
        syncState = .downloading(completed: 0, total: total)
        progress?(SYSAssetProgress(completedPacks: 0, totalPacks: total, bytesDownloaded: 0, totalBytes: 0))

        // Through `ensure`, not `downloadAndInstall` directly: a launch-time
        // sync, a foreground resume and a tap on a tile can all want the same
        // pack at once, and `ensure` is what makes them share one download
        // instead of racing to unzip into the same folder.
        let ids = toDownload.map(\.id)
        var nextIndex = min(Self.maxConcurrentDownloads, ids.count)

        let outcome: @MainActor @Sendable (String) async -> (String, Bool) = { [self] id in
            await ensureOutcome(id)
        }

        await withTaskGroup(of: (String, Bool).self) { group in
            for id in ids.prefix(nextIndex) {
                group.addTask { await outcome(id) }
            }

            for await (id, succeeded) in group {
                completed += 1
                if !succeeded { failed.append(id) }
                syncState = .downloading(completed: completed, total: total)
                progress?(SYSAssetProgress(completedPacks: completed, totalPacks: total, bytesDownloaded: 0, totalBytes: 0))

                if nextIndex < ids.count {
                    let id = ids[nextIndex]
                    nextIndex += 1
                    group.addTask { await outcome(id) }
                }
            }
        }

        self.dataVersion = dataVersion
        syncState = failed.isEmpty ? .ready : .failed(itemIds: failed)
    }

    private func ensureOutcome(_ id: String) async -> (String, Bool) {
        if case .success = await ensure(id) { return (id, true) }
        return (id, false)
    }

    private func removeObsoleteItems(currentItems: [Item]) {
        let currentIds = Set(currentItems.map(\.id))
        let storedIds = Set(itemStates.keys)

        for obsoleteId in storedIds.subtracting(currentIds) {
            removeItem(id: obsoleteId)
        }
    }

    private func removeItem(id: String) {
        try? fm.removeItem(at: itemFolderURL(id: id))
        var map = itemChecksumMap
        map.removeValue(forKey: id)
        itemChecksumMap = map
        itemStates.removeValue(forKey: id)
    }

    /// Downloads `path`, verifies it against `checksum` (the encrypted
    /// bytes — the same order as before encryption existed), and decrypts
    /// it. Shared by `downloadAndInstall` (a manifest item, unzipped into
    /// place after) and `ensureBundle` (a companion asset an item points
    /// to but that isn't itself a manifest item — Prarthana's per-item
    /// audio, fetched only when played).
    private func downloadDecrypted(path: String, checksum: String?, id: String) async throws -> Data {
        guard let bundleURL = url(path: path) else {
            throw SYSContentSyncError.invalidBundleURL(itemId: id)
        }

        let tempFileURL: URL
        do {
            tempFileURL = try await SYSNetwork.shared.download(bundleURL)
        } catch {
            throw SYSContentSyncError.downloadFailed(itemId: id)
        }
        defer { try? fm.removeItem(at: tempFileURL) }

        // Every published pack is encrypted with this app's own App Store
        // id as the key — see SYSCrypto. The app never sees this step.
        guard let appStoreID = SYSHosting.contentID(bundle: bundle) else {
            throw SYSContentSyncError.installFailed(itemId: id)
        }

        // Hashing and decrypting a multi-megabyte pack is CPU work, and this
        // class is main-actor: done inline it stalls every frame for as long
        // as the pack is large, which on first launch is 20-odd packs in a
        // row. .mappedIfSafe avoids loading the bundle fully into memory.
        return try await Task.detached(priority: .utility) { () throws -> Data in
            guard let encrypted = try? Data(contentsOf: tempFileURL, options: .mappedIfSafe) else {
                throw SYSContentSyncError.downloadFailed(itemId: id)
            }
            if let checksum {
                guard SYSHash.sha256Hex(encrypted).caseInsensitiveCompare(checksum) == .orderedSame else {
                    throw SYSContentSyncError.checksumMismatch(itemId: id)
                }
            }
            do {
                return try SYSCrypto.decrypt(encrypted, appStoreID: appStoreID)
            } catch {
                throw SYSContentSyncError.installFailed(itemId: id)
            }
        }.value
    }

    /// Downloads a companion bundle for an item — something an item's own
    /// extra fields point to but that isn't itself one of this manifest's
    /// items (Prarthana's per-item audio: fetched only the first time it's
    /// played, not eagerly with everything else). Same download, checksum
    /// and decrypt as any item; cached under `cacheKey` (reusing the same
    /// checksum map `downloadAndInstall` does), so a second call for the
    /// same audio — the same checksum — never re-downloads.
    public func ensureBundle(_ path: String, checksum: String?, cacheKey: String) async -> Result<Data, SYSContentSyncError> {
        let destination = bundlesRoot.appendingPathComponent(cacheKey)
        if let checksum, itemChecksumMap[cacheKey] == checksum,
           let cached = try? Data(contentsOf: destination) {
            return .success(cached)
        }

        do {
            let plaintext = try await downloadDecrypted(path: path, checksum: checksum, id: cacheKey)
            try fm.createDirectory(at: bundlesRoot, withIntermediateDirectories: true)
            try plaintext.write(to: destination, options: .atomic)
            if let checksum {
                saveItemChecksum(checksum, for: cacheKey)
            }
            return .success(plaintext)
        } catch let error as SYSContentSyncError {
            return .failure(error)
        } catch {
            return .failure(.installFailed(itemId: cacheKey))
        }
    }

    private func downloadAndInstall(_ item: Item) async throws {
        let plaintext = try await downloadDecrypted(path: item.bundle, checksum: item.checksum, id: item.id)

        let plaintextTempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = workingRoot.appendingPathComponent(item.id)
        let archive = isArchive(item.bundle)
        try? fm.removeItem(at: destination)
        do {
            // Off the main actor for the same reason as the decrypt above —
            // writing and unzipping a whole pack is not a UI-thread job.
            try await Task.detached(priority: .utility) {
                let fm = FileManager.default
                try plaintext.write(to: plaintextTempURL, options: .atomic)
                if archive {
                    try SYSZip.unzip(at: plaintextTempURL, to: destination)
                } else {
                    // A single-file item (a festival year's JSON, say) — the
                    // decrypted bytes ARE its index.json; nothing to unpack.
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                    try fm.moveItem(at: plaintextTempURL, to: destination.appendingPathComponent("index.json"))
                }
            }.value
            try? fm.removeItem(at: plaintextTempURL)
        } catch {
            try? fm.removeItem(at: plaintextTempURL)
            try? fm.removeItem(at: destination)
            throw SYSContentSyncError.installFailed(itemId: item.id)
        }

        try installIntoLive(from: destination, itemId: item.id)

        if let checksum = item.checksum {
            saveItemChecksum(checksum, for: item.id)
        }
    }

    /// A pack whose bundle ends `.zip` is many files that always travel
    /// together, unzipped on install. Anything else (a festival year's
    /// JSON, say) is one file — the same shape `SYSAssets` already
    /// distinguishes for its own packs.
    private func isArchive(_ bundlePath: String) -> Bool {
        (bundlePath as NSString).pathExtension.lowercased() == "zip"
    }

    /// Moves a downloaded item into place, keeping a backup until the swap
    /// succeeds so a failure mid-install restores what was there before.
    private func installIntoLive(from sourceFolder: URL, itemId: String) throws {
        let liveItemFolder = itemFolderURL(id: itemId)
        let backupFolder = backupRoot.appendingPathComponent(itemId)

        try? fm.removeItem(at: backupFolder)

        if !fm.fileExists(atPath: itemsRoot.path) {
            try fm.createDirectory(at: itemsRoot, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: liveItemFolder.path) {
            try fm.moveItem(at: liveItemFolder, to: backupFolder)
        }

        do {
            try fm.moveItem(at: sourceFolder, to: liveItemFolder)
            try? fm.removeItem(at: backupFolder)
        } catch {
            try? fm.removeItem(at: liveItemFolder)
            if fm.fileExists(atPath: backupFolder.path) {
                try? fm.moveItem(at: backupFolder, to: liveItemFolder)
            }
            throw error
        }
    }

    // MARK: - Content reads

    public func loadItemIndex<T: Decodable>(id: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: itemIndexURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func loadFile(itemId: String, filename: String) -> Data? {
        try? Data(contentsOf: itemFolderURL(id: itemId).appendingPathComponent(filename))
    }

    public func fileURL(itemId: String, filename: String) -> URL? {
        let fileURL = itemFolderURL(id: itemId).appendingPathComponent(filename)
        return fm.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// Every file a downloaded item unzipped to, sorted by name — for a pack
    /// whose contents aren't named in the manifest and are just "whatever
    /// the zip has" (Colorful's SVGs, page order being sorted filenames).
    /// Empty for an item that isn't downloaded, or isn't an archive.
    public func filenames(itemId: String) -> [String] {
        let names = try? fm.contentsOfDirectory(atPath: itemFolderURL(id: itemId).path)
        return (names ?? []).sorted()
    }

    // MARK: - Cleanup

    public func clearAllData() {
        try? fm.removeItem(at: rootURL)
        createDirectoriesIfNeeded()
        SYSSettings.shared.remove(dataVersionKey)
        SYSSettings.shared.remove(itemChecksumMapKey)
        itemStates.removeAll()
    }
}
