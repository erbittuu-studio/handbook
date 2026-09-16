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
    private let requiresConfig: Bool
    private let launchEvent: SYSAnalyticsEvent?
    private var isRunning = false

    /// - Parameters:
    ///   - requiresAssets: true for apps with nothing in the bundle to fall back
    ///     on, so startup fails closed instead of reaching a screen with nothing
    ///     to draw.
    ///   - requiresConfig: true for apps that ship no config of their own, so a
    ///     first launch that cannot fetch one stops at the blocker instead of
    ///     running on empty defaults with no maintenance switch and no minimum
    ///     version. Later launches are unaffected: once a copy is on the device
    ///     a failed refresh is simply an offline app carrying on.
    ///   - launchEvent: tracked once the launch is known to be usable. The app
    ///     owns the event; this owns when it fires, so a launch blocked by
    ///     maintenance or a failed download is not counted as a normal open.
    public init(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        requiresConfig: Bool = false,
        launchEvent: SYSAnalyticsEvent? = nil
    ) {
        self.config = config
        self.onboardingEnabled = onboardingEnabled
        self.requiresAssets = requiresAssets
        self.requiresConfig = requiresConfig
        self.launchEvent = launchEvent
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

        let resolved = await SYSBootstrap.start(
            config: config,
            onboardingEnabled: onboardingEnabled,
            requiresAssets: requiresAssets,
            requiresConfig: requiresConfig,
            assetProgress: { [weak self] update in self?.progress = update }
        )
        await settle(resolved, afterReady: afterReady)
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
                assetProgress: { [weak self] update in self?.progress = update }
            )
            await self.settle(resolved, afterReady: afterReady)
        }
    }

    /// Moves past onboarding or release notes once the app's screen is done.
    public func advance() {
        state = SYSBootstrap.resume(config: config)
    }

    private func settle(_ resolved: SYSAppState, afterReady: (() async -> Void)?) async {
        if case .dataUnavailable = resolved {
            state = resolved
            return
        }
        await afterReady?()
        if let launchEvent {
            SYSAnalytics.shared.track(launchEvent)
        }
        progress = nil
        state = resolved
    }
}
#endif
