import Foundation
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

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

/// When the sync may fetch what is missing without being asked: never (`onDemand`), only on an unmetered
/// connection (`unmetered`), or on any connection (`anyNetwork`). It applies after each refresh, when the
/// connection returns and when the app comes back to the foreground.
public enum SYSDownloadPolicy: Sendable {
    case onDemand
    case unmetered
    case anyNetwork
}

/// Whether an item can be opened now: it is on the device, it needs a connection to be fetched, or fetching failed.
public enum SYSItemAccess: Sendable {
    case ready
    case needsInternet
    case failed
}

private let sysReceiptName = ".sys-receipt"

public enum SYSContentSyncError: Error {
    case invalidBundleURL(itemId: String)
    case downloadFailed(itemId: String)
    case checksumMismatch(itemId: String)
    case installFailed(itemId: String)
}

/// One large file a manifest lists beside its items: where to fetch it, its checksum, and the name it is kept under.
public struct SYSBundleRequest: Sendable {
    public let path: String
    public let checksum: String?
    public let cacheKey: String

    public init(path: String, checksum: String?, cacheKey: String) {
        self.path = path
        self.checksum = checksum
        self.cacheKey = cacheKey
    }
}

@MainActor
/// Generic on-disk cache + downloader for a manifest's items: the live/staging/backup/downloads layout, checksum trackin...
public final class SYSContentSync<Item: SYSContentItem>: ObservableObject {
    @Published public private(set) var items: [Item] = [] { didSet { reportReadiness() } }
    @Published public private(set) var itemStates: [String: SYSContentItemStatus] = [:] { didSet { reportReadiness() } }
    @Published public private(set) var syncState: SYSContentSyncState = .idle

    private let fm = FileManager.default
    private let storageFolder: String
    private let dataVersionKey: SYSSettingsKey<Int>
    private let itemChecksumMapKey: SYSSettingsKey<[String: String]>
    private let bundle: Bundle

    public let manifestName: String

    private var explicitBaseURL: String?
    private var manifestETag: String?
    private var keptAssets: [String] = []
    private var keptBundles: [SYSBundleRequest] = []
    private var resuming = false
    private var refreshing = 0
    #if canImport(Combine)
    private var observers: [AnyCancellable] = []
    #endif

    private var lastRefresh: Date?

    public var downloadPolicy: SYSDownloadPolicy = .onDemand
    /// How long a refreshed manifest is trusted while the app stays in use; after that, coming back to the app
    /// refreshes it again (only when the policy allows downloads).
    public var refreshInterval: TimeInterval = 6 * 3600
    /// Called whenever a refresh ends, whoever started it, so the app can adopt the manifest and what it lists.
    public var didRefresh: (() -> Void)?
    private var inFlightEnsures: [String: Task<Result<Void, SYSContentSyncError>, Never>] = [:]

    #if canImport(CoreSpotlight) && !os(watchOS)
    private var searchKind: String?
    private var searchPublisher: (@MainActor () -> Void)?
    private var searchTask: Task<Void, Never>?
    #endif

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
        recoverInterruptedInstalls()
        SYSResetRegistry.register(self)
        observeReturn()
    }

    public func configure(baseURL: String) {
        self.explicitBaseURL = baseURL
    }

    #if canImport(CoreSpotlight) && !os(watchOS)
    /// Puts every downloaded item into system search and keeps it there, on a background actor; the app only says how one item reads.
    public func indexForSearch(
        kind: String,
        describe: @escaping @Sendable (Item, SYSContentFolder) async -> SYSSearchEntry?
    ) where Item: Sendable {
        searchKind = kind
        searchPublisher = { [weak self] in
            guard let self else { return }
            let ready = items
                .filter { itemStates[$0.id] == .downloaded }
                .map { ($0, SYSContentFolder(url: itemFolderURL(id: $0.id))) }
            Task.detached(priority: .utility) {
                await SYSSearchIndexer.shared.replace(kind: kind) {
                    var entries: [SYSSearchEntry] = []
                    for (item, folder) in ready {
                        if let entry = await describe(item, folder) { entries.append(entry) }
                    }
                    return entries
                }
            }
        }
        scheduleSearchIndex()
    }

    private func scheduleSearchIndex() {
        guard let searchPublisher else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, self != nil else { return }
            searchPublisher()
        }
    }

    private func forgetSearchIndex() {
        searchTask?.cancel()
        guard let kind = searchKind else { return }
        Task.detached(priority: .utility) { await SYSSearchIndexer.shared.forget(kind: kind) }
    }
    #else
    private func scheduleSearchIndex() {}
    private func forgetSearchIndex() {}
    #endif

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

    private func isItemAvailable(id: String, checksum: String?) -> Bool {
        guard itemExists(id: id) else { return false }
        guard let checksum else { return true }
        let folder = itemFolderURL(id: id)
        if let receipt = try? String(contentsOf: folder.appendingPathComponent(sysReceiptName), encoding: .utf8) {
            return receipt == checksum
        }
        guard itemChecksumMap[id] == checksum else { return false }
        try? checksum.write(to: folder.appendingPathComponent(sysReceiptName), atomically: true, encoding: .utf8)
        return true
    }

    private func recoverInterruptedInstalls() {
        let kept = (try? fm.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)) ?? []
        for backup in kept {
            let live = itemsRoot.appendingPathComponent(backup.lastPathComponent)
            if fm.fileExists(atPath: live.path) {
                try? fm.removeItem(at: backup)
            } else {
                try? fm.createDirectory(at: itemsRoot, withIntermediateDirectories: true)
                try? fm.moveItem(at: backup, to: live)
            }
        }
        let leftovers = (try? fm.contentsOfDirectory(at: workingRoot, includingPropertiesForKeys: nil)) ?? []
        for leftover in leftovers { try? fm.removeItem(at: leftover) }
    }

    private func itemExists(id: String) -> Bool {
        let contents = try? fm.contentsOfDirectory(atPath: itemFolderURL(id: id).path)
        return !(contents ?? []).isEmpty
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
        createDirectoriesIfNeeded()
        refreshing += 1
        defer {
            refreshing -= 1
            didRefresh?()
        }
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
            lastRefresh = Date()
            persistRawManifest(data)
            lastManifestError = nil
            let visible = SYSPublishing.visible(decoded.items)
            if downloadAll {
                await sync(items: visible, dataVersion: decoded.manifestVersion, progress: progress)
            } else {
                loadCached(visible)
                self.dataVersion = decoded.manifestVersion
                syncState = .ready
                downloadInBackground(visible, dataVersion: decoded.manifestVersion, progress: progress)
            }
        } catch SYSNetworkError.notModified {
            lastRefresh = Date()
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
                if let cached = loadLocalManifest(as: MinimalManifest.self) {
                    downloadInBackground(
                        SYSPublishing.visible(cached.items),
                        dataVersion: cached.manifestVersion,
                        progress: progress
                    )
                }
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
        createDirectoriesIfNeeded()
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
                self.scheduleSearchIndex()
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
        if hasCachedContent || items.isEmpty && syncState.isReady {
            return .success(())
        }
        switch syncState {
        case let .failed(itemIds):
            return .failure(.corrupt(pack: itemIds.joined(separator: ", ")))
        case .manifestUnavailable, .ready, .idle, .downloading:
            return .failure(lastManifestError ?? .offline)
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
        scheduleSearchIndex()
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
        scheduleSearchIndex()
        await downloadMissing(items: items, dataVersion: remoteVersion, progress: progress)
    }

    private static var maxConcurrentDownloads: Int { 3 }

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
        scheduleSearchIndex()
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
        let destination = bundleURL(cacheKey, checksum: checksum)
        if isBundleKept(checksum: checksum, cacheKey: cacheKey), let cached = try? Data(contentsOf: destination) {
            return .success(cached)
        }

        do {
            let plaintext = try await downloadDecrypted(path: path, checksum: checksum, id: cacheKey)
            try fm.createDirectory(at: bundlesRoot, withIntermediateDirectories: true)
            try plaintext.write(to: destination, options: .atomic)
            removeOtherVersions(of: cacheKey, keeping: destination)
            return .success(plaintext)
        } catch let error as SYSContentSyncError {
            return heldBundle(cacheKey) ?? .failure(error)
        } catch {
            return heldBundle(cacheKey) ?? .failure(.installFailed(itemId: cacheKey))
        }
    }

    /// A large file listed beside the items, such as audio, is kept under a name that carries its checksum, so the
    /// file existing means it is complete and current, with nothing else to keep in step.
    private func bundleURL(_ cacheKey: String, checksum: String?) -> URL {
        bundlesRoot.appendingPathComponent(checksum.map { "\(cacheKey)-\($0.prefix(16))" } ?? cacheKey)
    }

    func isBundleKept(checksum: String?, cacheKey: String) -> Bool {
        let kept = bundleURL(cacheKey, checksum: checksum)
        if fm.fileExists(atPath: kept.path) { return true }
        let legacy = bundlesRoot.appendingPathComponent(cacheKey)
        guard checksum != nil, itemChecksumMap[cacheKey] == checksum, fm.fileExists(atPath: legacy.path) else { return false }
        try? fm.moveItem(at: legacy, to: kept)
        itemChecksumMap[cacheKey] = nil
        return fm.fileExists(atPath: kept.path)
    }

    private func versions(of cacheKey: String) -> [URL] {
        let names = (try? fm.contentsOfDirectory(atPath: bundlesRoot.path)) ?? []
        return names
            .filter { $0 == cacheKey || ($0.hasPrefix(cacheKey + "-") && $0.count == cacheKey.count + 17) }
            .map { bundlesRoot.appendingPathComponent($0) }
    }

    private func removeOtherVersions(of cacheKey: String, keeping kept: URL) {
        for other in versions(of: cacheKey) where other != kept { try? fm.removeItem(at: other) }
    }

    private func heldBundle(_ cacheKey: String) -> Result<Data, SYSContentSyncError>? {
        versions(of: cacheKey).lazy.compactMap { try? Data(contentsOf: $0) }.first.map { .success($0) }
    }

    // MARK: - Keeping content on the device

    private func isConnected(unmetered: Bool) -> Bool {
        #if canImport(Combine) && canImport(Network)
        return unmetered ? SYSConnectivity.shared.allowsOptionalDownloads : SYSConnectivity.shared.isOnline
        #else
        return true
        #endif
    }

    private var mayDownloadNow: Bool {
        switch downloadPolicy {
        case .onDemand: return false
        case .unmetered: return isConnected(unmetered: true)
        case .anyNetwork: return isConnected(unmetered: false)
        }
    }

    /// Pictures the manifest lists, such as category covers. They are kept beside the items and re-fetched whenever
    /// the connection returns; a picture already kept is only re-checked once a day.
    public func keepAssets(_ paths: [String]) {
        keptAssets = paths
        keepExtras()
    }

    /// Large companion files the manifest lists, such as audio. They wait for an unmetered connection; until then
    /// `ensureBundle` still fetches one on demand. A copy already kept is left alone.
    public func keepBundles(_ requests: [SYSBundleRequest]) {
        keptBundles = requests
        keepExtras()
    }

    private func keepExtras() {
        guard downloadPolicy != .onDemand else { return }
        #if canImport(UIKit) && !os(watchOS)
        let urls = keptAssets.compactMap { url(path: $0) }
        if !urls.isEmpty, isConnected(unmetered: false) {
            Task.detached(priority: .utility) { await SYSImageStore.shared.prefetch(urls, unmetered: false) }
        }
        #endif
        let pending = keptBundles.filter { !isBundleKept(checksum: $0.checksum, cacheKey: $0.cacheKey) }
        guard !pending.isEmpty, isConnected(unmetered: true) else { return }
        Task { [weak self] in
            for request in pending {
                guard let self, isConnected(unmetered: true) else { return }
                _ = await ensureBundle(request.path, checksum: request.checksum, cacheKey: request.cacheKey)
            }
        }
    }

    /// Fetches whatever is missing if the policy allows it right now. It runs by itself when the connection
    /// returns and when the app comes back to the foreground, and finishes under a background task so leaving the
    /// app does not stop the item being downloaded.
    public func resumeIfNeeded() {
        guard downloadPolicy != .onDemand, !resuming, refreshing == 0, mayDownloadNow else { return }
        let missing = items.isEmpty || items.contains { itemStates[$0.id] != .downloaded }
        let stale = lastRefresh.map { Date().timeIntervalSince($0) > refreshInterval } ?? false
        guard missing || stale else { return keepExtras() }
        resuming = true
        SYSBackgroundTask.run("content-resume") { [weak self] in
            guard let self else { return }
            await refresh(downloadAll: true)
            keepExtras()
            resuming = false
        }
    }

    private func downloadInBackground(_ items: [Item], dataVersion: Int, progress: SYSAssetProgressHandler?) {
        guard mayDownloadNow else { return }
        if case .downloading = syncState { return }
        Task { await downloadMissing(items: items, dataVersion: dataVersion, progress: progress) }
    }

    private func observeReturn() {
        #if canImport(Combine) && canImport(Network)
        SYSConnectivity.shared.$isOnline
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.resumeIfNeeded() } }
            .store(in: &observers)
        #endif
        #if canImport(Combine) && canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.resumeIfNeeded() } }
            .store(in: &observers)
        #endif
    }

    private func reportReadiness() {
        #if canImport(Combine)
        let missing = items.filter { itemStates[$0.id] != .downloaded }.count
        SYSContentReadiness.shared.report(ObjectIdentifier(self), missing: missing)
        #endif
    }

    /// Whether this item can be opened: yes when it is on the device, otherwise it is fetched now when there is a
    /// connection, and `needsInternet` or `failed` says why it cannot be.
    public func access(_ id: String) async -> SYSItemAccess {
        if isAvailable(id: id) { return .ready }
        guard isConnected(unmetered: false) else { return .needsInternet }
        if case .success = await ensure(id) { return .ready }
        return isConnected(unmetered: false) ? .failed : .needsInternet
    }

    #if os(iOS)
    /// Opens an item for the caller: true when it is ready, otherwise a notice tells the person why it is not.
    @discardableResult
    public func open(_ id: String, languages: [String] = Locale.preferredLanguages) async -> Bool {
        let result = await access(id)
        if result != .ready { SYSContentNotice.show(result, languages: languages) }
        return result == .ready
    }
    #endif

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

        if let checksum = item.checksum {
            try? checksum.write(to: destination.appendingPathComponent(sysReceiptName), atomically: true, encoding: .utf8)
        }
        try installIntoLive(from: destination, itemId: item.id)
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
        return (names ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    public func clearAllData() {
        try? fm.removeItem(at: rootURL)
        createDirectoriesIfNeeded()
        SYSSettings.shared.remove(dataVersionKey)
        SYSSettings.shared.remove(itemChecksumMapKey)
        itemStates.removeAll()
    }
}

extension SYSContentSync: SYSResettable {
    /// Stops every download and forgets the manifest, its ETag and every item, so the next launch fetches everything again.
    public func resetForFreshInstall() {
        for running in inFlightEnsures.values { running.cancel() }
        inFlightEnsures.removeAll()
        forgetSearchIndex()
        manifestETag = nil
        lastManifestError = nil
        items = []
        syncState = .idle
        clearAllData()
    }
}
