import Foundation

/// One entry in the shared portfolio catalog (`app.json`) — the studio's own
/// apps, described once so nothing else has to duplicate a fact PES already
/// has. See `SYSHosting.baseURL`.
public struct SYSAppCatalogEntry: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String?
    public var iconPath: String?
    public var bundleId: String?
    public var appStoreUrl: String?
    public var category: String?
}

struct SYSAppCatalogData: Codable, Equatable, Sendable {
    var version: Int?
    var baseUrl: String?
    var apps: [SYSAppCatalogEntry]?
}

/// Fetches and caches `app.json` — one file, read by every app and by the
/// studio website, so a fact stated there (an app's name, icon, store URL)
/// never has to be repeated in `config.json` too.
public final class SYSAppCatalog {
    public static let shared = SYSAppCatalog()

    private var data: SYSAppCatalogData?
    private let bundle: Bundle
    private let network: SYSNetwork
    private let fileManager: FileManager

    private static let fileName = "app.json"

    public init(
        bundle: Bundle = .main,
        network: SYSNetwork = .shared,
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.network = network
        self.fileManager = fileManager
    }

    /// A previous fetch, if one is cached on disk. Synchronous and local, same
    /// contract as `SYSConfig.load()`.
    public func load() {
        guard data == nil, let cached = cachedData() else { return }
        data = try? JSONDecoder().decode(SYSAppCatalogData.self, from: cached)
    }

    /// Fetches and caches for next launch.
    @discardableResult
    public func refresh() async -> Bool {
        guard let url = URL(string: "\(SYSHosting.baseURL)/\(Self.fileName)") else { return false }
        guard let (payload, _) = try? await network.data(url),
              let fetched = try? JSONDecoder().decode(SYSAppCatalogData.self, from: payload)
        else { return false }
        try? payload.write(to: cacheURL, options: .atomic)
        data = fetched
        return true
    }

    /// This app's own entry, matched by `SYSHosting.contentID()`.
    public var thisApp: SYSAppCatalogEntry? {
        guard let id = SYSHosting.contentID(bundle: bundle) else { return nil }
        return data?.apps?.first { $0.id == id }
    }

    private var cacheURL: URL {
        (try? SYSContent.file(Self.fileName, fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Self.fileName)
    }

    private func cachedData() -> Data? { try? Data(contentsOf: cacheURL) }

    /// Testing seam: inject data directly, bypassing the network and cache.
    func applyForTesting(_ data: SYSAppCatalogData) { self.data = data }
}
