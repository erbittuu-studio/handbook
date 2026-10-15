import Foundation

/// A string that may be provided per language: {"en": "...", "hi": "..."}.
public struct SYSLocalizedText: Codable, Hashable, Sendable {
    private(set) var values: [String: String]

    public init(_ values: [String: String]) { self.values = values }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = ["en": single]
        } else {
            values = (try? container.decode([String: String].self)) ?? [:]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    func resolved(for locales: [String] = Locale.preferredLanguages) -> String? {
        SYSLocale.match(values, for: locales)
    }

    public func text(for locales: [String] = Locale.preferredLanguages) -> String {
        resolved(for: locales) ?? ""
    }
}

extension SYSLocalizedText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(["en": value]) }
}

enum SYSLocale {
    static func match<Value>(
        _ values: [String: Value],
        for locales: [String] = Locale.preferredLanguages
    ) -> Value? {
        guard !values.isEmpty else { return nil }

        var byTag: [String: Value] = [:]
        for (key, value) in values { byTag[canonical(key)] = value }

        for locale in locales {
            let tag = canonical(locale)
            for candidate in narrowing(tag) {
                if let hit = byTag[candidate] { return hit }
            }
            if let language = tag.split(separator: "-").first.map(String.init),
               let widened = byTag.keys.filter({ $0.hasPrefix(language + "-") }).sorted().first {
                return byTag[widened]
            }
        }
        return byTag["en"] ?? byTag[byTag.keys.sorted()[0]]
    }

    private static func canonical(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func narrowing(_ tag: String) -> [String] {
        let parts = tag.split(separator: "-")
        guard !parts.isEmpty else { return [] }
        return (1...parts.count).reversed().map { parts.prefix($0).joined(separator: "-") }
    }
}

enum SYSValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    case array([SYSValue]), object([String: SYSValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([SYSValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: SYSValue].self) { self = .object(value); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var intValue: Int? { if case .int(let value) = self { return value }; return nil }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
}

struct SYSConfigData: Codable {
    struct Update: Codable {
        var minimumVersion: String?
        var recommendedVersion: String?
        var message: SYSLocalizedText?
    }

    struct Maintenance: Codable {
        var enabled: Bool?
        var message: SYSLocalizedText?
    }

    struct Rating: Codable {
        var minSessions: Int?
        var minDaysSinceInstall: Int?
    }

    struct Content: Codable {
        var baseURL: String?
        var manifestPath: String?
    }

    var version: Int?
    var update: Update?
    var maintenance: Maintenance?
    var flags: [String: Bool]?
    var rating: Rating?
    var urls: [String: String]?
    var content: Content?
    var manifests: [String]?
    var supportEmail: String?
    var whatsNew: [String: [String: [String]]]?
    var app: [String: SYSValue]?

    init() {}

    func app<T: Decodable>(as type: T.Type) -> T? {
        guard let section = app else { return nil }
        do {
            let json = try JSONEncoder().encode(section)
            return try JSONDecoder().decode(type, from: json)
        } catch {
            SYSLogger.error("config: app section did not decode as \(type) — \(error)")
            return nil
        }
    }
}

enum SYSConfigOutcome: Equatable, Sendable {
    case updated
    case unchanged
    case failed(SYSContentError)
}

final class SYSConfig: @unchecked Sendable {
    static let shared = SYSConfig()

    var data: SYSConfigData { state.value.data }

    private struct State {
        var data = SYSConfigData()
        var remoteURL: URL?
    }

    private let state: SYSLocked<State>

    private let bundle: Bundle
    private let network: SYSNetwork
    private let fileManager: FileManager

    private static let fileName = "config.json"
    private static let etagKey = SYSSettingsKey<String?>("sys.config.etag", default: nil)

    init(
        bundle: Bundle = .main,
        network: SYSNetwork = .shared,
        fileManager: FileManager = .default,
        remoteURL: URL? = nil
    ) {
        self.bundle = bundle
        self.network = network
        self.fileManager = fileManager
        self.state = SYSLocked(State(remoteURL: remoteURL))
    }

    var hasLocalCopy: Bool { cachedData() != nil || bundledData() != nil }

    func applyForTesting(_ data: SYSConfigData) { state.withLock { $0.data = data } }

    func load() {
        let bundled = decode(bundledData())
        let cached = decode(cachedData())

        if let cached, (cached.version ?? 0) >= (bundled?.version ?? 0) {
            state.withLock { $0.data = cached }
        } else if let bundled {
            state.withLock { $0.data = bundled }
        }
    }

    @discardableResult
    func refresh() async -> SYSConfigOutcome {
        guard let remoteURL = state.value.remoteURL ?? SYSHosting.configURL(bundle: bundle) else {
            return .failed(.notConfigured)
        }

        do {
            let etag = cachedData() == nil ? nil : SYSSettings.shared[Self.etagKey]
            let (payload, newETag) = try await network.data(remoteURL, etag: etag)
            guard let fetched = decode(payload) else {
                return .failed(.unreadableManifest("config.json"))
            }

            guard (fetched.version ?? 0) >= (data.version ?? 0) else { return .unchanged }

            try? payload.write(to: cacheURL, options: .atomic)
            SYSSettings.shared[Self.etagKey] = newETag
            state.withLock { $0.data = fetched }
            return .updated
        } catch SYSNetworkError.notModified {
            return cachedData() == nil
                ? .failed(.unreadableManifest("304 with nothing cached"))
                : .unchanged
        } catch SYSNetworkError.offline {
            return .failed(.offline)
        } catch let SYSNetworkError.http(status) {
            return .failed(.server(status: status))
        } catch let SYSNetworkError.decoding(detail) {
            return .failed(.unreadableManifest(detail))
        } catch {
            SYSLogger.debug("config refresh failed: \(error)")
            return .failed(.offline)
        }
    }

    func flag(_ key: String, default fallback: Bool = false) -> Bool {
        data.flags?[key] ?? fallback
    }

    func url(_ key: String) -> URL? {
        guard let raw = data.urls?[key] else { return nil }
        return URL(string: raw, relativeTo: SYSHosting.contentURL(bundle: bundle))?.absoluteURL
    }

    func value(_ key: String) -> SYSValue? { data.app?[key] }

    func app<T: Decodable>(as type: T.Type) -> T? { data.app(as: type) }

    var currentVersion: String { SYSVersion.current(bundle: bundle) }

    private var cacheURL: URL {
        (try? SYSContent.file(Self.fileName, fileManager))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(Self.fileName)
    }

    private func cachedData() -> Data? { try? Data(contentsOf: cacheURL) }

    private func bundledData() -> Data? {
        bundle.url(forResource: "config", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
    }

    private func decode(_ payload: Data?) -> SYSConfigData? {
        payload.flatMap { try? JSONDecoder().decode(SYSConfigData.self, from: $0) }
    }
}
