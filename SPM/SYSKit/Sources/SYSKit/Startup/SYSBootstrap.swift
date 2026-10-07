import Foundation

/// What "download the required content" means for this app — a SYSContentSync instance's own prepareRequired (possibly c...
public typealias SYSPrepareContent =
    @MainActor @Sendable (SYSAssetProgressHandler?) async -> Result<Void, SYSContentError>

/// A download-progress callback, hopped to the main actor before touching UI.
public typealias SYSAssetProgressHandler = @MainActor @Sendable (SYSAssetProgress) -> Void

/// Paired cleanup after SYSPrepareContent succeeds — a SYSContentSync- based app's own, or omitted if it has nothing to ...
public typealias SYSPruneContent = @MainActor @Sendable () async -> Void

/// What the app should show once startup finishes.
public enum SYSAppState: Equatable {
    case maintenance(message: String?)
    case updateRequired(message: String?, storeURL: URL?)
    case onboarding
    case whatsNew([String])
    case dataUnavailable(SYSContentError)
    case ready
}

enum SYSBootstrap {
    static var gateRefreshTimeout: TimeInterval {
        get { refreshTimeout.value }
        set { refreshTimeout.value = newValue }
    }

    private static let refreshTimeout = SYSLocked<TimeInterval>(1.0)

    static func start(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        backgroundAssets: Bool = false,
        requiresConfig: Bool = false,
        assetProgress: SYSAssetProgressHandler? = nil,
        prepareContent: SYSPrepareContent? = nil,
        pruneContent: SYSPruneContent? = nil
    ) async -> SYSAppState {
        config.load()
        SYSAppCatalog.shared.load()

        SYSLifecycle.recordLaunch(config: config)

        if let blocked = await fetchConfig(config, required: requiresConfig, waitsForRefresh: false) {
            return blocked
        }

        Task { await SYSAppCatalog.shared.refresh() }

        let prepare = prepareContent ?? Self.unconfiguredPrepareContent
        let prune = pruneContent ?? {}

        if backgroundAssets {
            await beginBackgroundAssetDownload(progress: assetProgress, prepareContent: prepare, pruneContent: prune)
        }

        if let gated = await gate(config: config) {
            return gated
        }

        // Content after the gates: a maintenance or update screen must appear even where nothing can download
        if requiresAssets {
            let prepared = await prepare(assetProgress)
            if case let .failure(error) = prepared {
                SYSLogger.error("startup: required content unavailable — \(error)")
                return .dataUnavailable(error)
            }
            await prune()
        }

        if onboardingEnabled, SYSOnboarding.shouldShow {
            return .onboarding
        }

        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }

        return .ready
    }

    static func retryContent(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresConfig: Bool = false,
        assetProgress: SYSAssetProgressHandler? = nil,
        prepareContent: SYSPrepareContent? = nil
    ) async -> SYSAppState {
        if let blocked = await fetchConfig(config, required: requiresConfig, waitsForRefresh: true) {
            return blocked
        }
        if SYSMaintenance.isActive(config: config) {
            return .maintenance(message: SYSMaintenance.message(config: config))
        }

        let prepare = prepareContent ?? Self.unconfiguredPrepareContent
        let prepared = await prepare(assetProgress)
        if case let .failure(error) = prepared { return .dataUnavailable(error) }
        return resume(config: config, onboardingEnabled: onboardingEnabled)
    }

    static func resume(config: SYSConfig = .shared, onboardingEnabled: Bool = true) -> SYSAppState {
        if onboardingEnabled, SYSOnboarding.shouldShow { return .onboarding }
        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }
        return .ready
    }

    static func gate(config: SYSConfig) async -> SYSAppState? {
        if SYSMaintenance.isActive(config: config) {
            SYSLogger.info("startup: maintenance mode")
            return .maintenance(message: SYSMaintenance.message(config: config))
        }
        if SYSUpdate.status(config: config) == .required {
            SYSLogger.info("startup: update required")
            return .updateRequired(
                message: SYSUpdate.message(config: config),
                storeURL: await SYSUpdate.storeURL()
            )
        }
        return nil
    }

    private static func fetchConfig(_ config: SYSConfig, required: Bool, waitsForRefresh: Bool) async -> SYSAppState? {
        guard required, !config.hasLocalCopy else {
            if waitsForRefresh || !config.hasLocalCopy {
                await refreshWithTimeout(config: config)
            }
            return nil
        }

        if case let .failed(error) = await config.refresh() {
            SYSLogger.error("startup: config unavailable — \(error)")
            return .dataUnavailable(error)
        }
        return nil
    }

    private static func refreshWithTimeout(config: SYSConfig) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await config.refresh() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(gateRefreshTimeout * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
    }

    @MainActor
    static func beginBackgroundAssetDownload(
        progress: SYSAssetProgressHandler?,
        prepareContent: SYSPrepareContent? = nil,
        pruneContent: SYSPruneContent? = nil
    ) {
        let prepare = prepareContent ?? Self.unconfiguredPrepareContent
        let prune = pruneContent ?? {}
        SYSBackgroundTask.run("sys.assets.background") {
            let result = await prepare(progress)
            if case let .failure(error) = result {
                SYSLogger.debug("content: background download did not complete — \(error)")
                return
            }
            await prune()
        }
    }

    private static let unconfiguredPrepareContent: SYSPrepareContent = { _ in
        SYSLogger.error("startup: requiresAssets/backgroundAssets is true but no prepareContent was given")
        return .failure(.notConfigured)
    }
}
