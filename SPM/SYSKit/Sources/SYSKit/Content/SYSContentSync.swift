import Foundation

/// One content item a manifest lists — the handful of fields the generic sync loop actually touches.
public protocol SYSContentItem: Codable, Identifiable, SYSPublishable where ID == String {
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

@MainActor
/// Generic on-disk cache + downloader for a manifest's items: the live/staging/backup/downloads layout, checksum trackin...
public final class SYSContentSync<Item: SYSContentItem>: ObservableObject {
    @Published public private(set) var items: [Item] = []
    @Published public private(set) var itemStates: [String: SYSContentItemStatus] = [:]
    @Published public private(set) var syncState: SYSContentSyncState = .idle

    private let fm = FileManager.default
    private let storageFolder: String
    private let dataVersionKey: SYSSettingsKey<Int>
    private let itemChecksumMapKey: SYSSettingsKey<[String: String]>
    private let bundle: Bundle

    public let manifestName: String

    private var explicitBaseURL: String?
    private var manifestETag: String?
    private var inFlightEnsures: [String: Task<Result<Void, SYSContentSyncError>, Never>] = [:]

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

    public func configure(baseURL: String) {
        self.explicitBaseURL = baseURL
    }

    var baseURL: String {
        if let explicitBaseURL { return explicitBaseURL }
        guard let root = SYSHosting.contentURL(bundle: bundle) else { return "" }
        return root.appendingPathComponent(manifestName, isDirectory: true).absoluteString
    }

    public func url(path: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(baseURL)/\(relative)")
    }

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
    var bundlesRoot: URL { liveRoot.appendingPathComponent("bundles") }

    private func createDirectoriesIfNeeded() {
        for dir in [rootURL, liveRoot, backupRoot, workingRoot, itemsRoot, bundlesRoot]
        where !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var root = rootURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

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

    public func loadLocalManifest<T: Decodable>(as type: T.Type) -> T? {
        guard fm.fileExists(atPath: liveManifestURL.path),
              let data = try? Data(contentsOf: liveManifestURL) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func manifest<T: Decodable>(as type: T.Type) -> T? {
        loadLocalManifest(as: type)
    }

    private struct MinimalManifest: Decodable {
        let manifestVersion: Int
        let items: [Item]
    }

    public private(set) var lastManifestError: SYSContentError?

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

    @discardableResult
    public func useCachedManifest() -> Bool { useCachedManifestIfAny() }

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
            return .success(())
        }
    }

    private func persistRawManifest(_ data: Data) {
        let dir = liveManifestURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? data.write(to: liveManifestURL, options: .atomic)
    }

    public func loadCached(_ items: [Item]) {
        self.items = items
        for item in items {
            itemStates[item.id] = isItemAvailable(id: item.id, checksum: item.checksum) ? .downloaded : .notDownloaded
        }
    }

    func loadBundled(_ items: [Item]) {
        self.items = items
        for item in items {
            itemStates[item.id] = .downloaded
        }
        syncState = .ready
    }

    public func isAvailable(id: String) -> Bool {
        itemStates[id] == .downloaded
    }

    public var hasCachedContent: Bool {
        itemStates.values.contains(.downloaded)
    }

    public func meta(for id: String) -> Item? {
        items.first { $0.id == id }
    }

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

    private static var maxConcurrentDownloads: Int { 3 }

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

        guard let appStoreID = SYSHosting.contentID(bundle: bundle) else {
            throw SYSContentSyncError.installFailed(itemId: id)
        }

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
            try await Task.detached(priority: .utility) {
                let fm = FileManager.default
                try plaintext.write(to: plaintextTempURL, options: .atomic)
                if archive {
                    try SYSZip.unzip(at: plaintextTempURL, to: destination)
                } else {
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

    private func isArchive(_ bundlePath: String) -> Bool {
        (bundlePath as NSString).pathExtension.lowercased() == "zip"
    }

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

    public func filenames(itemId: String) -> [String] {
        let names = try? fm.contentsOfDirectory(atPath: itemFolderURL(id: itemId).path)
        return (names ?? []).sorted()
    }

    public func clearAllData() {
        try? fm.removeItem(at: rootURL)
        createDirectoriesIfNeeded()
        SYSSettings.shared.remove(dataVersionKey)
        SYSSettings.shared.remove(itemChecksumMapKey)
        itemStates.removeAll()
    }
}
