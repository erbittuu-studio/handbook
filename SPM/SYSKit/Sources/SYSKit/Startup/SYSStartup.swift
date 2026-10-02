#if canImport(Combine)
import Combine
import Foundation

/// Owns the launch sequence and the state a screen renders from.
///
/// `SYSBootstrap` already decides *what* to show. What was left in every app was
/// the machinery around it: hold the state, hold the download progress, hop the
/// progress to the main actor, reset both when retrying, run whatever has to
/// happen after a successful start, and track the launch at the right moment.
/// Identical everywhere, and easy to get subtly wrong — retrying without
/// clearing progress leaves a stale bar, and tracking the launch before the
/// gates means a blocked launch counts as a session.
///
/// ```swift
/// @StateObject private var startup = SYSStartup(requiresAssets: true)
///
/// var body: some Scene {
///     WindowGroup {
///         switch startup.state {
///         case .none:    LoadingView(progress: startup.progress?.fraction)
///         case .ready:   HomeView()
///         ...
///         }
///         .task { await startup.begin() }
///     }
/// }
/// ```
///
/// Renders nothing — it publishes state, the app owns every pixel. Combine is
/// Apple-only, so this file is compiled out where it does not exist; the rest of
/// SYSKit still builds and tests without it.
@MainActor
public final class SYSStartup: ObservableObject {
    /// What the app should show. Nil until the first pass finishes.
    @Published public private(set) var state: SYSAppState?
    /// Download progress while required content is fetched, nil otherwise.
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

    /// - Parameters:
    ///   - requiresAssets: true for apps with nothing in the bundle to fall back
    ///     on, so startup fails closed instead of reaching a screen with nothing
    ///     to draw.
    ///   - backgroundAssets: true to fetch the required packs without making
    ///     launch wait for them — open at once, fill in as they land. See
    ///     `SYSBootstrap.start`. `resumeBackgroundAssets()` is called again
    ///     automatically on every foreground by `SYSBootstrappedApp`, so a
    ///     download interrupted by the app being killed or backgrounded picks
    ///     up rather than starting over.
    ///   - requiresConfig: true for apps that ship no config of their own, so a
    ///     first launch that cannot fetch one stops at the blocker instead of
    ///     running on empty defaults with no maintenance switch and no minimum
    ///     version. Later launches are unaffected: once a copy is on the device
    ///     a failed refresh is simply an offline app carrying on.
    ///   - minimumSplash: the least time the splash stays up, so a launch that
    ///     is ready at once does not flash it. The first launch of an install
    ///     and every later one have their own time; `.none` (the default)
    ///     shows it only as long as loading takes, `.standard` is the studio's.
    ///   - launchEvent: tracked once the launch is known to be usable. The app
    ///     owns the event; this owns when it fires, so a launch blocked by
    ///     maintenance or a failed download is not counted as a normal open.
    ///   - prepareContent/pruneContent: see `SYSBootstrap.start`. Both default
    ///     to `SYSAssets` — an app on `SYSContentSync` passes its own instead.
    public init(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        backgroundAssets: Bool = false,
        requiresConfig: Bool = false,
        minimumSplash: SYSSplashDuration = .none,
        launchEvent: SYSAnalyticsEvent? = nil,
        prepareContent: SYSPrepareContent? = nil,
        pruneContent: SYSPruneContent? = nil
    ) {
        self.config = config
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

    /// Runs the launch sequence. Safe to call from `.task`, which SwiftUI may
    /// invoke more than once; the second call is ignored.
    ///
    /// - Parameter afterReady: runs before the state is published, so anything it
    ///   prepares — decoding downloaded packs, say — is in place before the first
    ///   screen appears rather than a frame later.
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

    /// Re-attempts any still-missing background packs. Called automatically by
    /// `SYSBootstrappedApp` on every foreground; a UIKit app calls this itself
    /// from `sceneDidBecomeActive`. A no-op unless `backgroundAssets` is set,
    /// and costs nothing once everything required has already arrived —
    /// `prepareContent` (or `SYSAssets.prepareRequired` by default) skips
    /// whatever is cached.
    public func resumeBackgroundAssets() {
        guard backgroundAssets else { return }
        SYSBootstrap.beginBackgroundAssetDownload(
            progress: { [weak self] update in self?.progress = update },
            prepareContent: prepareContent,
            pruneContent: pruneContent
        )
    }

    /// Re-attempts the content download after `.dataUnavailable`.
    ///
    /// Clears the previous state and progress first: a retry that leaves the old
    /// bar on screen looks like it resumed something it did not.
    public func retry(afterReady: (() async -> Void)? = nil) {
        guard !isRunning else { return }
        // Set before the Task, not inside it. Inside, a second tap runs between
        // the guard and the Task body and passes — so an impatient double-tap on
        // "Try again" starts two retries against the same packs.
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

    /// Moves past onboarding or release notes once the app's screen is done.
    public func advance() {
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
    }
}
#endif
