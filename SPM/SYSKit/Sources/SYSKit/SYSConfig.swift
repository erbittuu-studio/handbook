import Foundation

// MARK: - Localised text

/// A string that may be provided per language: `{"en": "...", "hi": "..."}`.
///
/// Also accepts a bare string, so a single-locale app can write
/// `"message": "text"` and expand it later without breaking older builds.
public struct SYSLocalizedText: Codable, Equatable, Sendable {
    private var values: [String: String]

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

    /// Best match for the device language, falling back to English, then to
    /// whatever exists. Never nil when any text was provided.
    public func resolved(for locales: [String] = Locale.preferredLanguages) -> String? {
        SYSLocale.match(values, for: locales)
    }
}

extension SYSLocalizedText: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(["en": value]) }
}

// MARK: - Locale matching

/// Picks the best-fitting entry from text keyed by language tag.
///
/// Two-letter prefix matching isn't enough: `zh-Hans`/`zh-Hant` both truncate
/// to `zh`, and `pt-BR` never matches a lookup for `pt`. Tags are matched most
/// specific first, narrowing one subtag at a time (`zh-Hant-TW`, `zh-Hant`,
/// `zh`), case- and separator-insensitive.
public enum SYSLocale {
    /// The value whose key best fits `locales`, or nil when there is nothing.
    public static func match<Value>(
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
            // Widen the other way: `pt` takes `pt-BR` over English. Sorted so
            // the choice is stable rather than dictionary hash order.
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

// MARK: - Value

/// Minimal type-erased JSON value, so the `app` object can hold mixed types
/// without pulling in a dependency.
public enum SYSValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    case array([SYSValue]), object([String: SYSValue]), null

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var intValue: Int? { if case .int(let value) = self { return value }; return nil }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var doubleValue: Double? { if case .double(let value) = self { return value }; return nil }
}

// MARK: - Model

/// The shape of `config.json`. Everything except `app` is standard across apps.
///
/// Every field is optional: a config missing a key degrades to a default
/// rather than failing to decode.
public struct SYSConfigData: Codable {
    public struct Update: Codable {
        /// Below this the app must not be usable. See `SYSUpdate`.
        public var minimumVersion: String?
        /// Below this, nudge — but let the user continue.
        public var recommendedVersion: String?
        public var message: SYSLocalizedText?
    }

    public struct Maintenance: Codable {
        public var enabled: Bool?
        public var message: SYSLocalizedText?
    }

    public struct Rating: Codable {
        public var minSessions: Int?
        public var minDaysSinceInstall: Int?
    }

    /// Where remote content lives, for apps shipping content packs.
    public struct Content: Codable {
        public var baseURL: String?
        public var manifestPath: String?
    }

    /// Promotes the studio's other apps without shipping a build.
    public struct CrossPromo: Codable {
        public struct Item: Codable {
            public var bundleId: String?
            public var name: String?
            public var iconURL: String?
            public var storeURL: String?
        }
        public var enabled: Bool?
        public var apps: [Item]?
    }

    public var version: Int?
    public var updatedAt: String?
    public var update: Update?
    public var maintenance: Maintenance?
    public var flags: [String: Bool]?
    public var rating: Rating?
    public var urls: [String: String]?
    public var content: Content?
    public var crossPromo: CrossPromo?
    /// Release notes per version: `{"2.5.0": {"en": ["…"]}}`.
    public var whatsNew: [String: [String: [String]]]?
    /// App-specific values, so apps differ without forking this package.
    public var app: [String: SYSValue]?

    public init() {}

    /// The `app` section decoded into a type the app defines.
    public func app<T: Decodable>(as type: T.Type) -> T? {
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

/// What a refresh actually did.
///
/// Distinguishes "nothing changed" (a 304, or a remote copy no newer than
/// what's held) from "nothing arrived" (offline, error) — a first launch with
/// nothing bundled needs to tell those apart.
public enum SYSConfigOutcome: Equatable, Sendable {
    /// Newer config arrived and is in force.
    case updated
    /// The local copy is already current. Nothing to do and nothing wrong.
    case unchanged
    /// Nothing arrived. An app holding a local copy carries on with it.
    case failed(SYSContentError)
}

// MARK: - Manager

/// Loads config at launch, serves it synchronously, refreshes in the background.
///
/// Sources in order of preference: a cached copy from a previous fetch, the copy
/// bundled with the app, then empty defaults. Can never end up worse than what
/// shipped.
///
/// A fetched config normally applies on the **next** launch, so values stay
/// stable for a whole session. `SYSBootstrap` is the one exception: it waits
/// briefly for a refresh before evaluating the maintenance and force-update
/// gates.
public final class SYSConfig {
    public static let shared = SYSConfig()

    public private(set) var data = SYSConfigData()

    private let bundle: Bundle
    private let network: SYSNetwork
    private let fileManager: FileManager
    private var remoteURL: URL?

    private static let fileName = "config.json"
    private static let etagKey = SYSSettingsKey<String?>("sys.config.etag", default: nil)

    public init(
        bundle: Bundle = .main,
        network: SYSNetwork = .shared,
        fileManager: FileManager = .default,
        remoteURL: URL? = nil
    ) {
        self.bundle = bundle
        self.network = network
        self.fileManager = fileManager
        self.remoteURL = remoteURL
    }

    /// Whether any config is held on this device — a previous fetch, or a
    /// bundled copy for apps that still ship one.
    public var hasLocalCopy: Bool { cachedData() != nil || bundledData() != nil }

    /// Where to fetch from. Usually derived from `SYSHosting.contentURL()`.
    public func setRemoteURL(_ url: URL?) { remoteURL = url }

    /// Injects config directly, bypassing bundle and cache. Tests only.
    func applyForTesting(_ data: SYSConfigData) { self.data = data }

    // MARK: Lifecycle

    /// Call once, as early as possible at launch, before anything reads a value.
    /// Synchronous and local — no network — so it cannot delay startup.
    public func load() {
        let bundled = decode(bundledData())
        let cached = decode(cachedData())

        // Prefer the cache only if genuinely newer than the bundled copy.
        if let cached, (cached.version ?? 0) >= (bundled?.version ?? 0) {
            data = cached
        } else if let bundled {
            data = bundled
        }
    }

    /// Fetches and stores for next launch. See `SYSConfigOutcome`.
    @discardableResult
    public func refresh() async -> SYSConfigOutcome {
        // Not configured means "the usual place", not "no remote config" —
        // the URL is derivable from SYSContentID.
        guard let remoteURL = remoteURL ?? SYSHosting.configURL(bundle: bundle) else {
            return .failed(.notConfigured)
        }

        do {
            // Only claim to hold a copy when the file is actually there — the
            // etag and the file can drift apart (restore, wipe, stray delete).
            let etag = cachedData() == nil ? nil : SYSSettings.shared[Self.etagKey]
            let (payload, newETag) = try await network.data(remoteURL, etag: etag)
            guard let fetched = decode(payload) else {
                return .failed(.unreadableManifest("config.json"))
            }

            // Never accept something older than what's held.
            guard (fetched.version ?? 0) >= (data.version ?? 0) else { return .unchanged }

            try? payload.write(to: cacheURL, options: .atomic)
            SYSSettings.shared[Self.etagKey] = newETag
            data = fetched
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

    // MARK: Accessors

    public func flag(_ key: String, default fallback: Bool = false) -> Bool {
        data.flags?[key] ?? fallback
    }

    /// Resolves against `SYSHosting.contentURL()`, so `urls` in config.json may
    /// give either a full URL or a path relative to this app's own content
    /// folder (`"Web/support.html"`) — one shared base, not repeated per app.
    public func url(_ key: String) -> URL? {
        guard let raw = data.urls?[key] else { return nil }
        return URL(string: raw, relativeTo: SYSHosting.contentURL(bundle: bundle))?.absoluteURL
    }

    /// Other apps to promote, excluding this one. Empty when disabled, so
    /// callers need no extra check.
    public var crossPromoApps: [SYSConfigData.CrossPromo.Item] {
        guard data.crossPromo?.enabled == true else { return [] }
        return (data.crossPromo?.apps ?? []).filter { $0.bundleId != bundle.bundleIdentifier }
    }

    /// App-specific value from the `app` object.
    public func value(_ key: String) -> SYSValue? { data.app?[key] }

    /// The `app` section decoded into a type the app defines.
    ///
    /// ```swift
    /// struct RealAIAppConfig: Decodable {
    ///     let maxRecentPages: Int
    ///     let showSeasonalPack: Bool
    /// }
    /// let tuning = SYSConfig.shared.app(as: RealAIAppConfig.self)
    /// ```
    ///
    /// Returns nil if the section is absent or doesn't match the type, and
    /// logs why — a config the app can't read falls back to its own defaults.
    public func app<T: Decodable>(as type: T.Type) -> T? { data.app(as: type) }

    public var currentVersion: String { SYSVersion.current(bundle: bundle) }

    // MARK: Storage

    /// Application Support, not Caches — the system can purge Caches, and a
    /// purged config would strand an app with nothing to start from.
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
