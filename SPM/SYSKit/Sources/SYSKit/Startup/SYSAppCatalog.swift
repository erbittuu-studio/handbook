import Foundation

struct SYSAppCatalogEntry: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var tagline: String?
    var iconPath: String?
    var appStoreUrl: String?
    var category: String?

    var iconURL: URL? {
        guard let iconPath else { return nil }
        return URL(string: "\(SYSHosting.baseURL)/\(id)/\(iconPath)")
    }
}

struct SYSAppCatalogData: Codable, Equatable, Sendable {
    var version: Int?
    var baseUrl: String?
    var apps: [SYSAppCatalogEntry]?
}

final class SYSAppCatalog: @unchecked Sendable {
    static let shared = SYSAppCatalog()

    private let catalog = SYSLocked<SYSAppCatalogData?>(nil)
    private let bundle: Bundle
    private let network: SYSNetwork
    private let fileManager: FileManager

    private static let fileName = "app.json"

    init(
        bundle: Bundle = .main,
        network: SYSNetwork = .shared,
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.network = network
        self.fileManager = fileManager
    }

    func load() {
        guard catalog.value == nil, let cached = cachedData() else { return }
        catalog.value = try? JSONDecoder().decode(SYSAppCatalogData.self, from: cached)
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let url = URL(string: "\(SYSHosting.baseURL)/\(Self.fileName)") else { return false }
        guard let (payload, _) = try? await network.data(url),
              let fetched = try? JSONDecoder().decode(SYSAppCatalogData.self, from: payload)
        else { return false }
        try? payload.write(to: cacheURL, options: .atomic)
        catalog.value = fetched
        return true
    }

    var thisApp: SYSAppCatalogEntry? {
        guard let id = SYSHosting.contentID(bundle: bundle) else { return nil }
        return catalog.value?.apps?.first { $0.id == id }
    }

    var otherApps: [SYSAppCatalogEntry] {
        let ownID = SYSHosting.contentID(bundle: bundle)
        return (catalog.value?.apps ?? []).filter { $0.id != ownID }
    }

    private var cacheURL: URL {
        (try? SYSContent.file(Self.fileName, fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Self.fileName)
    }

    private func cachedData() -> Data? { try? Data(contentsOf: cacheURL) }

    func applyForTesting(_ data: SYSAppCatalogData) { catalog.value = data }
}
