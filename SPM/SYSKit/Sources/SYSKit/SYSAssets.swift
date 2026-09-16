import Foundation

/// One downloadable pack of content, as named by the manifest.
public struct SYSAssetPack: Codable, Equatable, Sendable {
    public let id: String
    /// What to call this pack, in the reader's language.
    ///
    /// A plain `"title": "Baby"` still decodes — `SYSLocalizedText` reads a bare
    /// string as `{"en": …}` — so a manifest written before this change is
    /// unaffected. Serving `{"en": "Baby", "ar": "الرضّع"}` instead means
    /// renaming or retranslating a pack is a deploy rather than a release.
    public let title: SYSLocalizedText?
    /// Site-relative path, e.g. `/packs/seaworld-3446a234.json`.
    public let bundle: String
    public let bytes: Int?
    /// Hex SHA-256 of the pack bytes. Checked before a pack is accepted.
    public let sha256: String?
    /// Packs the app cannot start without. Absent means false.
    public let required: Bool?

    public init(id: String, title: SYSLocalizedText? = nil, bundle: String,
                bytes: Int? = nil, sha256: String? = nil, required: Bool? = nil) {
        self.id = id
        self.title = title
        self.bundle = bundle
        self.bytes = bytes
        self.sha256 = sha256
        self.required = required
    }
}

/// The index of everything the site hosts for this app.
public struct SYSAssetManifest: Codable, Equatable, Sendable {
    public let manifestVersion: Int
    public let generatedAt: String?
    public let items: [SYSAssetPack]

    public init(manifestVersion: Int, generatedAt: String? = nil, items: [SYSAssetPack]) {
        self.manifestVersion = manifestVersion
        self.generatedAt = generatedAt
        self.items = items
    }
}

/// Why the app could not get something it needs from the server.
///
/// Covers all three: the config, the manifest, and the packs. They fail in the
/// same ways and, to the person holding the phone, they are one situation —
/// "we could not reach the server" — not three. One type means one mapping from
/// error to sentence in the app, and one answer to whether a retry is honest.
public enum SYSContentError: Error, Equatable, Sendable {
    /// No usable network. Retrying is the right offer.
    case offline
    /// The server answered, and the answer was a failure.
    case server(status: Int)
    /// Downloaded bytes did not match the hash the manifest published.
    case corrupt(pack: String)
    /// The manifest could not be read.
    case unreadableManifest(String)
    /// The manifest is a newer format than this build understands.
    case unsupportedManifest(version: Int)
    /// A required pack is not in the manifest at all.
    case missingRequiredPack(id: String)
    /// `configure` was never called.
    case notConfigured
    /// The pack arrived and did not match the type the app asked for.
    case decoding(String)

    /// Whether offering "try again" is honest.
    ///
    /// Apps kept deciding this individually and would eventually disagree — a
    /// retry button on a 404 re-fetches the same 404, and on a hash mismatch it
    /// re-downloads the same bad bytes. Both need a fix on the server, not
    /// another tap.
    public var isRetryable: Bool {
        switch self {
        case .offline:
            return true
        case let .server(status):
            // 5xx is usually transient; 4xx will answer identically next time.
            return status >= 500
        case .corrupt, .unreadableManifest, .decoding:
            // The bytes are what the server published; asking again gets them
            // again. Either the app or the pack has to change.
            return false
        case .unsupportedManifest, .missingRequiredPack, .notConfigured:
            return false
        }
    }

    /// Whether the user needs a newer build rather than another attempt.
    public var requiresAppUpdate: Bool {
        if case .unsupportedManifest = self { return true }
        return false
    }
}

/// Progress through a `prepareRequired` run, for apps that show a bar.
public struct SYSAssetProgress: Equatable, Sendable {
    public let completedPacks: Int
    public let totalPacks: Int
    public let bytesDownloaded: Int
    public let totalBytes: Int

    public var fraction: Double {
        totalBytes > 0
            ? Double(bytesDownloaded) / Double(totalBytes)
            : (totalPacks > 0 ? Double(completedPacks) / Double(totalPacks) : 0)
    }
}

/// Downloads and caches the content an app ships separately from its binary.
///
/// Fetches an index, downloads what's required before the first screen,
/// verifies it, and keeps it for next launch — an app writes screens, not a
/// download manager.
///
/// A pack is opaque here — bytes with an id and a hash. What's inside is the
/// app's business and this layer never decodes it, which is why the same
/// code serves all of them; `ensure` hands back `Data` and the app decides
/// what it means.
///
/// Renders nothing, like the rest of SYSKit — `prepareRequired` returns a
/// result and the app decides what to show. `SYSBootstrap` folds it into
/// startup for apps that want the standard sequence.
///
/// Cached in Application Support (backed up, not evictable under storage
/// pressure). Downloads are written to a temporary file and moved into place
/// only after the hash matches, so an interrupted download is never mistaken
/// for a complete one.
public actor SYSAssets {
    public static let shared = SYSAssets()

    /// Highest manifest format this build understands.
    public static let supportedManifestVersion = 1

    private let network: SYSNetwork
    private let fileManager: FileManager

    private var explicitBaseURL: URL?
    /// Configured, or this app's folder under the shared content root
    /// (`SYSHosting.contentURL()`).
    private var baseURL: URL? { explicitBaseURL ?? SYSHosting.contentURL() }
    private var explicitRequired: [String] = []
    private var cachedManifest: SYSAssetManifest?
    private var manifestETag: String?
    /// Downloads already running, keyed by pack id.
    ///
    /// Two taps on the same category, or a category tapped while startup is still
    /// fetching it, otherwise download the same bytes twice. Every app that
    /// downloads content hits this, so it is solved here rather than in each app.
    private var inFlight: [String: Task<Result<Data, SYSContentError>, Never>] = [:]

    /// Attempts per pack before giving up, with a short backoff between them.
    /// The app's retry button is the real recovery path; this only rides out a
    /// blip so a single dropped packet does not become an error screen.
    public var attemptsPerPack: Int = 3
    public var retryBackoff: TimeInterval = 1.5

    public init(network: SYSNetwork = .shared, fileManager: FileManager = .default) {
        self.network = network
        self.fileManager = fileManager
    }

    // MARK: Configuration

    /// - Parameters:
    ///   - baseURL: site root, e.g. `https://raw.githubusercontent.com/.../content/abclearning`.
    ///   - required: pack ids the app cannot start without. Leave empty to rely
    ///     on the manifest's own `required` flags.
    /// Only needed for a custom domain, a staging site, or an explicit required
    /// list. Otherwise the site is derived and the manifest's own `required`
    /// flags decide what startup waits for.
    public func configure(baseURL: URL? = nil, required: [String] = []) {
        self.explicitBaseURL = baseURL
        self.explicitRequired = required
    }

    public var manifest: SYSAssetManifest? { cachedManifest }

    // MARK: Cache locations

    /// Where packs live — `Content/packs`. Created on demand.
    ///
    /// The layout, and the backup exclusion that goes with it, belong to
    /// `SYSContent`: this and `SYSConfig` both keep their files there, in the
    /// shape the site serves them.
    public func cacheDirectory() throws -> URL {
        try SYSContent.packs(fileManager)
    }

    /// Local file for a pack, whether or not it exists yet. Named after the
    /// remote filename, which carries the content hash — a new version lands
    /// beside the old one rather than overwriting it.
    public func localURL(for pack: SYSAssetPack) throws -> URL {
        let name = (pack.bundle as NSString).lastPathComponent
        return try cacheDirectory().appendingPathComponent(name)
    }

    public func isCached(_ pack: SYSAssetPack) -> Bool {
        guard let url = try? localURL(for: pack) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    /// Bytes of a cached pack, or nil if it is not downloaded.
    public func cachedData(for pack: SYSAssetPack) -> Data? {
        guard let url = try? localURL(for: pack) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Every pack already on disk, as (id, bytes). Decoding stays with the
    /// app, since only it knows what's inside.
    public func cachedPacks() -> [(id: String, data: Data)] {
        guard let manifest = cachedManifest ?? loadPersistedManifest() else { return [] }
        return manifest.items.compactMap { pack in
            guard let data = cachedData(for: pack) else { return nil }
            return (id: pack.id, data: data)
        }
    }

    // MARK: Manifest

    /// The manifest this device already holds, in memory or on disk.
    private func heldManifest() -> SYSAssetManifest? {
        if let cachedManifest { return cachedManifest }
        if let restored = loadPersistedManifest() {
            cachedManifest = restored
            return restored
        }
        return nil
    }

    @discardableResult
    public func refreshManifest() async -> Result<SYSAssetManifest, SYSContentError> {
        guard let baseURL else { return .failure(.notConfigured) }
        let url = baseURL.appendingPathComponent("manifest.json")

        do {
            let (value, etag) = try await network.get(url, as: SYSAssetManifest.self, etag: manifestETag)
            guard value.manifestVersion <= Self.supportedManifestVersion else {
                // Reading a newer format by guessing is how you ship a crash to
                // the installs you can least afford to break.
                SYSLogger.error("assets: manifest v\(value.manifestVersion) is newer than supported v\(Self.supportedManifestVersion)")
                return .failure(.unsupportedManifest(version: value.manifestVersion))
            }
            cachedManifest = value
            manifestETag = etag
            persistManifest(value)
            return .success(value)
        } catch SYSNetworkError.notModified {
            // The server says the copy we hold is current.
            if let restored = heldManifest() { return .success(restored) }
            return .failure(.unreadableManifest("304 with nothing cached"))
        } catch {
            // Anything else falls back to the manifest we hold, whatever went
            // wrong — a manifest from a previous launch plus the packs beside
            // it is a working app. Consulting the cache only for `offline`
            // errors used to send a fully-populated install with no network
            // (timeout, DNS failure, captive portal, 500...) to a "No
            // connection" screen despite having all its content on disk.
            if let restored = heldManifest() {
                SYSLogger.debug("assets: manifest fetch failed, using the held copy — \(error)")
                return .success(restored)
            }

            // Nothing held: this is a first launch, and the reason matters
            // because it decides what the app is allowed to say.
            switch error {
            case SYSNetworkError.offline: return .failure(.offline)
            case let SYSNetworkError.http(status): return .failure(.server(status: status))
            case let SYSNetworkError.decoding(detail): return .failure(.unreadableManifest(detail))
            default: return .failure(.offline)
            }
        }
    }

    /// Beside `packs`, not inside it — the same place the site puts it.
    private var persistedManifestURL: URL? {
        try? SYSContent.file("manifest.json", fileManager)
    }

    private func persistManifest(_ manifest: SYSAssetManifest) {
        guard let url = persistedManifestURL,
              let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadPersistedManifest() -> SYSAssetManifest? {
        guard let url = persistedManifestURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SYSAssetManifest.self, from: data)
    }

    // MARK: Downloading

    /// Makes every required pack available locally.
    ///
    /// Safe to call again — already-cached packs are skipped, so an app's retry
    /// button costs only what is actually still missing.
    ///
    /// `progress` is delivered on the main actor: it exists to drive a progress
    /// bar, and every app was otherwise wrapping it in a `Task { @MainActor in }`
    /// to get there.
    @discardableResult
    public func prepareRequired(
        progress: (@MainActor @Sendable (SYSAssetProgress) -> Void)? = nil
    ) async -> Result<Void, SYSContentError> {
        let manifestResult = await refreshManifest()
        guard case let .success(manifest) = manifestResult else {
            if case let .failure(error) = manifestResult { return .failure(error) }
            return .failure(.notConfigured)
        }

        let wanted = requiredPacks(in: manifest)
        if let missing = explicitRequired.first(where: { id in !manifest.items.contains { $0.id == id } }) {
            return .failure(.missingRequiredPack(id: missing))
        }

        let outstanding = wanted.filter { !isCached($0) }
        let totalBytes = outstanding.reduce(0) { $0 + ($1.bytes ?? 0) }
        var downloaded = 0
        var completed = wanted.count - outstanding.count

        await progress?(SYSAssetProgress(completedPacks: completed,
                                         totalPacks: wanted.count,
                                         bytesDownloaded: 0,
                                         totalBytes: totalBytes))

        for pack in outstanding {
            switch await fetchOnce(pack) {
            case .success:
                completed += 1
                downloaded += pack.bytes ?? 0
                await progress?(SYSAssetProgress(completedPacks: completed,
                                                 totalPacks: wanted.count,
                                                 bytesDownloaded: downloaded,
                                                 totalBytes: totalBytes))
            case let .failure(error):
                SYSLogger.error("assets: required pack \(pack.id) failed — \(error)")
                return .failure(error)
            }
        }

        SYSLogger.info("assets: \(wanted.count) required pack(s) ready")
        return .success(())
    }

    /// Makes one pack available, downloading it if needed. For content fetched
    /// on demand rather than at startup.
    @discardableResult
    public func ensure(_ packID: String) async -> Result<Data, SYSContentError> {
        guard let manifest = cachedManifest ?? loadPersistedManifest() else {
            let refreshed = await refreshManifest()
            guard case .success = refreshed else {
                if case let .failure(error) = refreshed { return .failure(error) }
                return .failure(.notConfigured)
            }
            return await ensure(packID)
        }
        guard let pack = manifest.items.first(where: { $0.id == packID }) else {
            return .failure(.missingRequiredPack(id: packID))
        }
        if let data = cachedData(for: pack) { return .success(data) }
        return await fetchOnce(pack)
    }

    /// `fetch`, but only one download per pack is ever in flight.
    private func fetchOnce(_ pack: SYSAssetPack) async -> Result<Data, SYSContentError> {
        if let running = inFlight[pack.id] { return await running.value }

        let task = Task { [weak self] in
            guard let self else { return Result<Data, SYSContentError>.failure(.notConfigured) }
            return await self.fetch(pack)
        }
        inFlight[pack.id] = task
        let result = await task.value
        inFlight[pack.id] = nil
        return result
    }

    /// One pack, downloaded if needed and decoded into the app's own type.
    ///
    /// The app owns the shape of a pack; this owns fetching, verifying and
    /// caching it. Handing the type in means no app writes the download-then-
    /// decode dance, and none of them can disagree about what a failure means.
    public func ensure<T: Decodable & Sendable>(
        _ packID: String,
        as type: T.Type
    ) async -> Result<T, SYSContentError> {
        switch await ensure(packID) {
        case let .success(data):
            return decode(data, as: type, packID: packID)
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Every cached pack, decoded. Skips packs that do not match the type rather
    /// than failing the lot: an app may host more than one kind of pack.
    public func cachedPacks<T: Decodable & Sendable>(as type: T.Type) -> [(id: String, value: T)] {
        cachedPacks().compactMap { pack in
            guard case let .success(value) = decode(pack.data, as: type, packID: pack.id) else { return nil }
            return (id: pack.id, value: value)
        }
    }

    private func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        packID: String
    ) -> Result<T, SYSContentError> {
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            SYSLogger.error("assets: pack \(packID) did not decode as \(type) — \(error)")
            return .failure(.decoding("\(packID): \(error)"))
        }
    }

    private func requiredPacks(in manifest: SYSAssetManifest) -> [SYSAssetPack] {
        if !explicitRequired.isEmpty {
            return manifest.items.filter { explicitRequired.contains($0.id) }
        }
        return manifest.items.filter { $0.required == true }
    }

    private func fetch(_ pack: SYSAssetPack) async -> Result<Data, SYSContentError> {
        guard let baseURL else { return .failure(.notConfigured) }
        let url = baseURL.appendingPathComponent(pack.bundle)

        var lastError: SYSContentError = .offline
        for attempt in 1 ... max(1, attemptsPerPack) {
            do {
                let (data, _) = try await network.data(url, timeout: 60)

                if let expected = pack.sha256 {
                    let actual = SYSHash.sha256Hex(data)
                    guard actual == expected.lowercased() else {
                        // Retrying a hash mismatch just re-downloads the same bad
                        // bytes; the server is wrong, not the connection.
                        SYSLogger.error("assets: \(pack.id) hash mismatch — expected \(expected.prefix(8)), got \(actual.prefix(8))")
                        return .failure(.corrupt(pack: pack.id))
                    }
                }

                do {
                    try writeAtomically(data, for: pack)
                } catch {
                    SYSLogger.error("assets: could not store \(pack.id) — \(error)")
                }
                return .success(data)
            } catch SYSNetworkError.offline {
                lastError = .offline
            } catch let SYSNetworkError.http(status) {
                lastError = .server(status: status)
                // 4xx will answer the same way next time.
                if (400 ..< 500).contains(status) { return .failure(lastError) }
            } catch {
                lastError = .offline
            }

            if attempt < attemptsPerPack {
                try? await Task.sleep(nanoseconds: UInt64(retryBackoff * Double(attempt) * 1_000_000_000))
            }
        }
        return .failure(lastError)
    }

    /// Writes to a sibling temporary file, then moves it into place, so a process
    /// killed mid-write leaves the old pack intact rather than a truncated one.
    private func writeAtomically(_ data: Data, for pack: SYSAssetPack) throws {
        let destination = try localURL(for: pack)
        try data.write(to: destination, options: .atomic)
    }

    // MARK: Housekeeping

    /// Deletes cached packs the manifest no longer names.
    ///
    /// Content-addressed filenames mean a replaced pack leaves its predecessor
    /// behind forever otherwise.
    @discardableResult
    public func pruneStalePacks() -> Int {
        guard let manifest = cachedManifest ?? loadPersistedManifest(),
              let directory = try? cacheDirectory(),
              let entries = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else { return 0 }

        // Only packs are in here now — the manifest sits beside the folder
        // rather than in it, so it no longer needs an exemption from the sweep.
        let live = Set(manifest.items.map { ($0.bundle as NSString).lastPathComponent })
        var removed = 0
        for entry in entries where !live.contains(entry) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(entry))
            removed += 1
        }
        if removed > 0 { SYSLogger.info("assets: pruned \(removed) stale pack(s)") }
        return removed
    }

    /// Removes everything. For a "clear downloaded content" setting.
    public func clearCache() {
        guard let directory = try? cacheDirectory() else { return }
        try? fileManager.removeItem(at: directory)
        cachedManifest = nil
        manifestETag = nil
    }
}
