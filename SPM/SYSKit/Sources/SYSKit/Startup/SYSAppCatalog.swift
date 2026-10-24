import Foundation

struct SYSAppCatalogEntry: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var tagline: String?
    var iconPath: String?
    var appStoreUrl: String?
    var urlScheme: String?
    var category: String?
    var recommends: [String]?
    var blurb: [String: String]?
    var highlights: [String: [String]]?

    func blurb(for languages: [String]) -> String? {
        let text = SYSLocale.match(blurb ?? [:], for: languages) ?? tagline
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }

    func highlights(for languages: [String]) -> [String] {
        SYSLocale.match(highlights ?? [:], for: languages) ?? []
    }

    var shortName: String {
        name.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    var iconURL: URL? {
        guard let iconPath else { return nil }
        return URL(string: "\(SYSHosting.baseURL)/\(id)/\(iconPath)")
    }
}

struct SYSAppCatalogData: Codable, Equatable, Sendable {
    var version: Int?
    var baseUrl: String?
    var apps: [SYSAppCatalogEntry]?
    var labels: [String: [String: String]]?
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
        #if canImport(UIKit) && !os(watchOS)
        let icons = (fetched.apps ?? []).compactMap(\.iconURL)
        Task.detached(priority: .utility) { await SYSImageStore.shared.prefetch(icons) }
        #endif
        return true
    }

    var thisApp: SYSAppCatalogEntry? {
        guard let id = SYSHosting.contentID(bundle: bundle) else { return nil }
        return catalog.value?.apps?.first { $0.id == id }
    }

    func label(_ key: String, for languages: [String] = Locale.preferredLanguages, fallback: String) -> String {
        let written = catalog.value?.labels?[key].flatMap { SYSLocale.match($0, for: languages) } ?? ""
        return written.isEmpty ? fallback : written
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

    func resetForFreshInstall() {
        catalog.value = nil
        try? fileManager.removeItem(at: cacheURL)
    }
}
