#if canImport(Combine)
import Combine
import Foundation

@MainActor
/// Owns the launch sequence and the state a screen renders from.
public final class SYSStartup: ObservableObject {
    @Published public private(set) var state: SYSAppState?
    @Published public private(set) var progress: SYSAssetProgress?

    private let config: SYSConfig
    private let onboardingEnabled: Bool
    private let requiresAssets: Bool
    private let backgroundAssets: Bool
    private let requiresConfig: Bool
    private let minimumSplash: SYSSplashDuration
    private let launchedAt = Date()
    private let prepareContent: SYSPrepareContent?
    private let pruneContent: SYSPruneContent?
    /// The startup of the running app, so a reset can start it again without the app wiring anything.
    public private(set) static weak var current: SYSStartup?

    private var isRunning = false
    private var afterReadyHandler: (() async -> Void)?
    private var deferredContent: Task<Result<Void, SYSContentError>, Never>?
    private var deferredResult: Result<Void, SYSContentError>?
    private var deferredAfterReady: (() async -> Void)?

    public init(
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        backgroundAssets: Bool = false,
        requiresConfig: Bool = false,
        minimumSplash: SYSSplashDuration = .none,
        prepareContent: SYSPrepareContent? = nil,
        pruneContent: SYSPruneContent? = nil
    ) {
        self.config = .shared
        self.onboardingEnabled = onboardingEnabled
        self.requiresAssets = requiresAssets
        self.backgroundAssets = backgroundAssets
        self.requiresConfig = requiresConfig
        self.minimumSplash = minimumSplash
        SYSLaunchMetrics.mark(.appLaunched)
        self.prepareContent = prepareContent
        self.pruneContent = pruneContent
        Self.current = self
    }

    public func begin(afterReady: (() async -> Void)? = nil) async {
        guard state == nil, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        afterReadyHandler = afterReady
        SYSLaunchMetrics.mark(.startupBegan)

        let resolved = await SYSBootstrap.start(
            config: config,
            onboardingEnabled: onboardingEnabled,
            requiresAssets: requiresAssets,
            backgroundAssets: backgroundAssets,
            requiresConfig: requiresConfig,
            deferContentForOnboarding: true,
            assetProgress: { [weak self] update in self?.progress = update },
            prepareContent: prepareContent,
            pruneContent: pruneContent
        )
        if requiresAssets, resolved == .onboarding, SYSAppState.debugForced == nil {
            deferredAfterReady = afterReady
            downloadWhileOnboarding()
            progress = nil
            state = resolved
            watchGates()
            return
        }
        await settle(resolved, afterReady: afterReady)
    }

    /// Starts the same content download the splash would have waited for, so it runs while the first-run flow is on screen.
    private func downloadWhileOnboarding() {
        let prepare = prepareContent
        let prune = pruneContent
        deferredResult = nil
        deferredContent = Task { [weak self] in
            let result = await (prepare ?? { _ in .failure(.notConfigured) })({ [weak self] update in self?.progress = update })
            if case .success = result { await prune?() }
            self?.deferredResult = result
            return result
        }
    }

    /// Begins the launch sequence again from nothing, after the app's data was erased.
    public func restart(afterReady: (() async -> Void)? = nil) {
        guard !isRunning else { return }
        deferredContent?.cancel()
        deferredContent = nil
        deferredResult = nil
        state = nil
        progress = nil
        let handler = afterReady ?? afterReadyHandler
        Task { await begin(afterReady: handler) }
    }

    func resumeBackgroundAssets() {
        guard backgroundAssets else { return }
        SYSBootstrap.beginBackgroundAssetDownload(
            progress: { [weak self] update in self?.progress = update },
            prepareContent: prepareContent,
            pruneContent: pruneContent
        )
    }

    func retry(afterReady: (() async -> Void)? = nil) {
        guard !isRunning else { return }
        isRunning = true
        state = nil
        progress = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            let resolved = await SYSBootstrap.retryContent(
                config: self.config,
                onboardingEnabled: self.onboardingEnabled,
                requiresConfig: self.requiresConfig,
                assetProgress: { [weak self] update in self?.progress = update },
                prepareContent: self.prepareContent
            )
            await self.settle(resolved, afterReady: afterReady)
        }
    }

    func advance() {
        guard let pending = deferredContent else {
            state = SYSBootstrap.resume(config: config, onboardingEnabled: onboardingEnabled)
            return
        }
        deferredContent = nil
        let afterReady = deferredAfterReady
        deferredAfterReady = nil
        if deferredResult == nil { state = nil }
        Task { [weak self] in
            guard let self else { return }
            let result = await pending.value
            if case let .failure(error) = result {
                self.progress = nil
                self.state = .dataUnavailable(error)
                return
            }
            await afterReady?()
            self.progress = nil
            self.state = SYSBootstrap.resume(config: self.config, onboardingEnabled: self.onboardingEnabled)
        }
    }

    private func settle(_ resolved: SYSAppState, afterReady: (() async -> Void)?) async {
        if let forced = SYSAppState.debugForced {
            state = forced
            return
        }
        if case .dataUnavailable = resolved {
            state = resolved
            return
        }
        await afterReady?()
        SYSLaunchMetrics.mark(.contentPrepared)
        await SYSTiming.pause(minimumSplash.remaining(
            isFirstLaunch: SYSLifecycle.isFirstLaunch,
            elapsed: Date().timeIntervalSince(launchedAt)
        ))
        progress = nil
        SYSLaunchMetrics.mark(.ready)
        state = resolved
        watchGates()
    }

    private func watchGates() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.config.refresh()
            guard let late = await SYSBootstrap.gate(config: self.config) else { return }
            switch self.state {
            case .ready?, .onboarding?, .whatsNew?: self.state = late
            default: break
            }
        }
    }
}
#endif
