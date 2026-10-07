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
    private let launchEvent: SYSAnalyticsEvent?
    private let prepareContent: SYSPrepareContent?
    private let pruneContent: SYSPruneContent?
    private var isRunning = false

    public init(
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        backgroundAssets: Bool = false,
        requiresConfig: Bool = false,
        minimumSplash: SYSSplashDuration = .none,
        launchEvent: SYSAnalyticsEvent? = nil,
        prepareContent: SYSPrepareContent? = nil,
        pruneContent: SYSPruneContent? = nil
    ) {
        self.config = .shared
        self.onboardingEnabled = onboardingEnabled
        self.requiresAssets = requiresAssets
        self.backgroundAssets = backgroundAssets
        self.requiresConfig = requiresConfig
        self.minimumSplash = minimumSplash
        self.launchEvent = launchEvent
        SYSLaunchMetrics.mark(.appLaunched)
        self.prepareContent = prepareContent
        self.pruneContent = pruneContent
    }

    public func begin(afterReady: (() async -> Void)? = nil) async {
        guard state == nil, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        SYSLaunchMetrics.mark(.startupBegan)

        let resolved = await SYSBootstrap.start(
            config: config,
            onboardingEnabled: onboardingEnabled,
            requiresAssets: requiresAssets,
            backgroundAssets: backgroundAssets,
            requiresConfig: requiresConfig,
            assetProgress: { [weak self] update in self?.progress = update },
            prepareContent: prepareContent,
            pruneContent: pruneContent
        )
        await settle(resolved, afterReady: afterReady)
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
        state = SYSBootstrap.resume(config: config, onboardingEnabled: onboardingEnabled)
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
        if let launchEvent {
            SYSAnalytics.shared.track(launchEvent)
        }
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
