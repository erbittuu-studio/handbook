#if canImport(UIKit) && !os(watchOS)
import CryptoKit
import ImageIO
import UIKit

/// Why a picture could not be loaded: no connection, or the server gave nothing usable.
public enum SYSImageError: Error, Equatable, Sendable {
    case offline
    case failed
}

final class SYSImageMemory: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

private struct SYSDecoded: @unchecked Sendable {
    let image: UIImage?
}

/// Every picture an app shows from a web address or a file goes through here.
///
/// A downloaded picture is kept in Application Support, which the system never empties to make room, and it
/// never expires: the app shows it offline for as long as it is installed. When online, a kept picture is
/// checked against the server at most once a day and replaced only by a good newer copy. A failed check or a
/// failed download never removes what is already kept. Apps call `prefetch` after their content syncs so every
/// picture they list is on the device before anyone scrolls to it.
public actor SYSImageStore {
    public static let shared = SYSImageStore()

    private struct Entry: Codable {
        var size: Int
        var used: Date
        var checked: Date
        var tag: String?
    }

    nonisolated let memory = SYSImageMemory()

    private let directory: URL?
    private let network: SYSNetwork
    private let limitBytes: Int
    private let recheckAfter: TimeInterval
    private var fetching: [String: Task<Void, Error>] = [:]
    private var validated: Set<String> = []
    private var touched: Set<String> = []
    private var loadedIndex: [String: Entry]?
    private var saving = false

    init(
        directory: URL? = nil,
        network: SYSNetwork? = nil,
        limitBytes: Int = 300_000_000,
        recheckAfter: TimeInterval = 86_400
    ) {
        self.directory = directory ?? Self.defaultDirectory()
        self.network = network ?? SYSNetwork(session: Self.makeSession())
        self.limitBytes = limitBytes
        self.recheckAfter = recheckAfter
    }

    /// The picture at this address or file, scaled down so its longest side is at most `maxPixelSize`.
    public func image(for url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        let side = Self.bucket(maxPixelSize)
        let memoryKey = Self.memoryKey(url, side)
        if let hit = memory.image(memoryKey) {
            revalidateIfDue(url)
            return hit
        }
        let file = try await localFile(for: url)
        let decoded = await Task.detached(priority: .userInitiated) {
            SYSDecoded(image: Self.downsample(file, side: side))
        }.value
        guard let image = decoded.image else { throw SYSImageError.failed }
        memory.store(image, for: memoryKey)
        return image
    }

    /// Downloads these pictures now, one after another. Optional pictures wait for an unmetered connection; the
    /// pictures a content manifest lists (`unmetered: false`) come down on any connection, as the content does.
    public func prefetch(_ urls: [URL], unmetered: Bool = true) async {
        let allowed = await MainActor.run {
            unmetered ? SYSConnectivity.shared.allowsOptionalDownloads : SYSConnectivity.shared.isOnline
        }
        guard allowed else { return }
        for url in urls where !url.isFileURL {
            if Task.isCancelled { return }
            let key = Self.key(url)
            if hasFile(key), !isDue(key) { continue }
            try? await download(url, key: key)
        }
    }

    func isCached(_ url: URL) -> Bool {
        url.isFileURL ? FileManager.default.fileExists(atPath: url.path) : hasFile(Self.key(url))
    }

    public nonisolated static func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        shared.memory.image(memoryKey(url, bucket(maxPixelSize)))
    }

    // MARK: - Files

    private func localFile(for url: URL) async throws -> URL {
        if url.isFileURL { return url }
        let key = Self.key(url)
        if hasFile(key) {
            markUsed(key)
            revalidateIfDue(url)
            return fileURL(key)
        }
        try await download(url, key: key)
        guard hasFile(key) else { throw SYSImageError.failed }
        return fileURL(key)
    }

    private func download(_ url: URL, key: String) async throws {
        if let running = fetching[key] { return try await running.value }
        let task = Task { try await self.fetch(url, key: key) }
        fetching[key] = task
        defer { fetching[key] = nil }
        try await task.value
    }

    private func fetch(_ url: URL, key: String) async throws {
        let had = hasFile(key)
        do {
            let (data, tag) = try await network.data(url, etag: had ? storedTag(key) : nil, timeout: 20)
            guard Self.isImage(data) else { throw SYSImageError.failed }
            try write(data, tag: tag, key: key)
            if had { memory.removeAll() }
            validated.insert(key)
        } catch SYSNetworkError.notModified {
            update(key) { $0.checked = Date() }
            validated.insert(key)
        } catch SYSNetworkError.offline {
            throw SYSImageError.offline
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SYSImageError.failed
        }
    }

    private func revalidateIfDue(_ url: URL) {
        guard !url.isFileURL else { return }
        let key = Self.key(url)
        guard !validated.contains(key), fetching[key] == nil, isDue(key) else { return }
        Task {
            let allowed = await MainActor.run { SYSConnectivity.shared.allowsOptionalDownloads }
            guard allowed else { return }
            try? await download(url, key: key)
        }
    }

    private func isDue(_ key: String) -> Bool {
        guard let checked = index[key]?.checked else { return true }
        return Date().timeIntervalSince(checked) > recheckAfter
    }

    private func hasFile(_ key: String) -> Bool {
        directory != nil && FileManager.default.fileExists(atPath: fileURL(key).path)
    }

    private func markUsed(_ key: String) {
        guard !touched.contains(key) else { return }
        touched.insert(key)
        update(key) { $0.used = Date() }
    }

    private func write(_ data: Data, tag: String?, key: String) throws {
        guard let directory else { throw SYSImageError.failed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(key), options: .atomic)
        let now = Date()
        var entries = index
        entries[key] = Entry(size: data.count, used: now, checked: now, tag: tag)
        loadedIndex = entries
        evictIfNeeded(keeping: key)
        scheduleSave()
    }

    private func storedTag(_ key: String) -> String? {
        index[key]?.tag
    }

    private var index: [String: Entry] {
        if let loadedIndex { return loadedIndex }
        let loaded = directory
            .flatMap { try? Data(contentsOf: $0.appendingPathComponent("index.json")) }
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        loadedIndex = loaded
        return loaded
    }

    private func update(_ key: String, _ change: (inout Entry) -> Void) {
        var entries = index
        guard var entry = entries[key] else { return }
        change(&entry)
        entries[key] = entry
        loadedIndex = entries
        scheduleSave()
    }

    private func scheduleSave() {
        guard !saving else { return }
        saving = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            saveIndex()
        }
    }

    private func saveIndex() {
        saving = false
        guard let directory, let data = try? JSONEncoder().encode(index) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }

    private func evictIfNeeded(keeping kept: String) {
        var entries = index
        var total = entries.values.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }
        for (key, entry) in entries.filter({ $0.key != kept }).sorted(by: { $0.value.used < $1.value.used })
        where total > limitBytes * 8 / 10 {
            try? FileManager.default.removeItem(at: fileURL(key))
            entries[key] = nil
            total -= entry.size
        }
        loadedIndex = entries
    }

    private func fileURL(_ key: String) -> URL {
        (directory ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(key).appendingPathExtension("img")
    }

    // MARK: - Helpers

    nonisolated static func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func memoryKey(_ url: URL, _ side: CGFloat) -> String {
        "\(url.absoluteString)@\(Int(side))"
    }

    nonisolated static func bucket(_ pixels: CGFloat) -> CGFloat {
        min(max((pixels / 256).rounded(.up) * 256, 256), 2048)
    }

    nonisolated static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    nonisolated static func downsample(_ file: URL, side: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, sourceOptions) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let longest = max(width, height)
        let target = longest > 0 ? min(side, CGFloat(longest)) : side
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static func defaultDirectory() -> URL? {
        let manager = FileManager.default
        guard var support = try? manager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        support.appendPathComponent("SYSImages", isDirectory: true)
        guard (try? manager.createDirectory(at: support, withIntermediateDirectories: true)) != nil else { return nil }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? support.setResourceValues(values)
        return support
    }
}
#endif
