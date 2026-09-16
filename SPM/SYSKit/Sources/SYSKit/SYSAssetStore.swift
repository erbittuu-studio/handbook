import Foundation

/// Keeps decoded packs in memory, so an app holds content rather than bytes.
///
/// `SYSAssets` fetches, verifies and caches pack *files*. Everything above that
/// was still being written per app: decode the bytes, remember which packs are
/// already decoded, skip the work on a second visit, drop it all when the cache
/// is cleared. That is bookkeeping, not product, and it is identical everywhere.
///
/// The app supplies the pack type and nothing else:
///
/// ```swift
/// struct ArtworkPack: Decodable, Sendable { let id: String; let pages: [Page] }
/// let store = SYSAssetStore<ArtworkPack>()
///
/// await store.adoptCached()              // whatever startup already downloaded
/// let pack = await store.pack("seaworld") // downloads and decodes if needed
/// ```
///
/// Renders nothing and knows nothing about what a pack contains — one app's
/// colouring pages are another's lesson data.
public actor SYSAssetStore<Pack: Decodable & Sendable> {
    private let assets: SYSAssets
    private var decoded: [String: Pack] = [:]

    public init(assets: SYSAssets = .shared) {
        self.assets = assets
    }

    // MARK: Reading

    /// A pack already decoded, without touching the network or the disk.
    public func loaded(_ packID: String) -> Pack? { decoded[packID] }

    public func isLoaded(_ packID: String) -> Bool { decoded[packID] != nil }

    /// Every pack decoded so far.
    public func all() -> [String: Pack] { decoded }

    public var count: Int { decoded.count }

    // MARK: Loading

    /// Decodes everything `SYSAssets` already has on disk.
    ///
    /// Call after startup: the required packs are downloaded by then, and this
    /// makes them available without a second request.
    @discardableResult
    public func adoptCached() async -> Int {
        let cached = await assets.cachedPacks(as: Pack.self)
        for entry in cached {
            decoded[entry.id] = entry.value
        }
        return cached.count
    }

    /// A pack, downloading and decoding it if it is not already in memory.
    ///
    /// `SYSAssets` coalesces concurrent downloads of the same pack, so calling
    /// this from several screens at once fetches the bytes once.
    public func pack(_ packID: String) async -> Result<Pack, SYSContentError> {
        if let existing = decoded[packID] { return .success(existing) }

        switch await assets.ensure(packID, as: Pack.self) {
        case let .success(value):
            decoded[packID] = value
            return .success(value)
        case let .failure(error):
            return .failure(error)
        }
    }

    /// Downloads the packs the app cannot start without, and decodes them.
    ///
    /// The startup equivalent of `pack(_:)`: `SYSBootstrap` already calls
    /// `SYSAssets.prepareRequired`, so use this when driving startup yourself.
    @discardableResult
    public func prepareRequired(
        progress: (@MainActor @Sendable (SYSAssetProgress) -> Void)? = nil
    ) async -> Result<Void, SYSContentError> {
        switch await assets.prepareRequired(progress: progress) {
        case .success:
            await adoptCached()
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    // MARK: Housekeeping

    /// Drops decoded packs. Pair with `SYSAssets.clearCache()`, or memory keeps
    /// serving content the disk no longer has.
    public func forgetAll() {
        decoded.removeAll()
    }

    /// Clears both the decoded packs and the files behind them.
    public func clearAll() async {
        await assets.clearCache()
        decoded.removeAll()
    }
}
