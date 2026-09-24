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

    public var baseURL: String = ""

    /// - Parameters:
    ///   - storageFolder: on-disk folder name under Application Support.
    ///   - dataVersionKey: pass the app's existing key if migrating from a
    ///     hand-rolled cache — the same key name is what makes existing
    ///     installs recognize what they already downloaded.
    ///   - itemChecksumMapKey: same migration note as `dataVersionKey`.
    public init(
        storageFolder: String,
        dataVersionKey: SYSSettingsKey<Int>,
        itemChecksumMapKey: SYSSettingsKey<[String: String]>
    ) {
        self.storageFolder = storageFolder
        self.dataVersionKey = dataVersionKey
        self.itemChecksumMapKey = itemChecksumMapKey
        createDirectoriesIfNeeded()
    }

    // MARK: - Configuration

    public func configure(baseURL: String) {
        self.baseURL = baseURL
    }

    public func url(path: String) -> URL? {
        URL(string: "\(baseURL)/\(path)")
    }

    // MARK: - Paths

    private var applicationSupportURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    public var rootURL: URL { applicationSupportURL.appendingPathComponent(storageFolder) }
    public var liveRoot: URL { rootURL.appendingPathComponent("live") }
    public var backupRoot: URL { rootURL.appendingPathComponent("backup") }
    public var workingRoot: URL { rootURL.appendingPathComponent("downloads") }
    public var itemsRoot: URL { liveRoot.appendingPathComponent("items") }
    public var liveManifestURL: URL { liveRoot.appendingPathComponent("manifest.json") }

    private func createDirectoriesIfNeeded() {
        for dir in [rootURL, liveRoot, backupRoot, workingRoot, itemsRoot] where !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Version / checksum tracking

    public var dataVersion: Int {
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
    public func sync(items: [Item], dataVersion remoteVersion: Int) async {
        let localVersion = dataVersion
        if localVersion > 0 && remoteVersion != localVersion {
            clearAllData()
        }

        self.items = items
        for item in items {
            itemStates[item.id] = isItemAvailable(id: item.id, checksum: item.checksum) ? .downloaded : .notDownloaded
        }

        removeObsoleteItems(currentItems: items)
        await downloadMissing(items: items, dataVersion: remoteVersion)
    }

    private func downloadMissing(items: [Item], dataVersion: Int) async {
        let toDownload = items.filter { itemStates[$0.id] != .downloaded }

        guard !toDownload.isEmpty else {
            syncState = .ready
            self.dataVersion = dataVersion
            return
        }

        let total = toDownload.count
        var failed: [String] = []
        syncState = .downloading(completed: 0, total: total)

        for (index, item) in toDownload.enumerated() {
            itemStates[item.id] = .downloading
            do {
                try await downloadAndInstall(item)
                itemStates[item.id] = .downloaded
            } catch {
                itemStates[item.id] = .failed
                failed.append(item.id)
            }
            syncState = .downloading(completed: index + 1, total: total)
        }

        self.dataVersion = dataVersion
        syncState = failed.isEmpty ? .ready : .failed(itemIds: failed)
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

    private func downloadAndInstall(_ item: Item) async throws {
        guard let bundleURL = url(path: item.bundle) else {
            throw SYSContentSyncError.invalidBundleURL(itemId: item.id)
        }

        let tempFileURL: URL
        do {
            tempFileURL = try await SYSNetwork.shared.download(bundleURL)
        } catch {
            throw SYSContentSyncError.downloadFailed(itemId: item.id)
        }

        if let expectedChecksum = item.checksum {
            // .mappedIfSafe avoids loading a large bundle fully into memory
            // for what is otherwise a one-shot startup check.
            guard let data = try? Data(contentsOf: tempFileURL, options: .mappedIfSafe),
                  SYSHash.sha256Hex(data).caseInsensitiveCompare(expectedChecksum) == .orderedSame
            else {
                try? fm.removeItem(at: tempFileURL)
                throw SYSContentSyncError.checksumMismatch(itemId: item.id)
            }
        }

        let destination = workingRoot.appendingPathComponent(item.id)
        try? fm.removeItem(at: destination)
        do {
            try SYSZip.unzip(at: tempFileURL, to: destination)
            try? fm.removeItem(at: tempFileURL)
        } catch {
            try? fm.removeItem(at: tempFileURL)
            try? fm.removeItem(at: destination)
            throw SYSContentSyncError.installFailed(itemId: item.id)
        }

        try installIntoLive(from: destination, itemId: item.id)

        if let checksum = item.checksum {
            saveItemChecksum(checksum, for: item.id)
        }
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

    // MARK: - Cleanup

    public func clearAllData() {
        try? fm.removeItem(at: rootURL)
        createDirectoriesIfNeeded()
        SYSSettings.shared.remove(dataVersionKey)
        SYSSettings.shared.remove(itemChecksumMapKey)
        itemStates.removeAll()
    }
}
