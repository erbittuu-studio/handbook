import Foundation

/// What the app should show once startup finishes.
public enum SYSAppState: Equatable {
    /// Something is wrong on our side — show the maintenance screen.
    case maintenance(message: String?)
    /// Too old to run. Block, and offer the store link.
    case updateRequired(message: String?, storeURL: URL?)
    /// First run of this onboarding version.
    case onboarding
    /// Just updated, and there are notes for this version.
    case whatsNew([String])
    /// Required content could not be downloaded, and the app cannot run without
    /// it. The app shows its own error screen; call `SYSBootstrap.retryContent()`
    /// from the retry button.
    case dataUnavailable(SYSContentError)
    /// Normal start — show home.
    case ready
}

/// Runs the standard startup sequence.
///
/// Every app does the same things in the same order at launch: load config,
/// record the launch, check the gates, decide what to show. Doing that once here
/// means an app writes screens, not startup plumbing.
///
/// Returns state; it renders nothing. Works the same from a SwiftUI `.task` or a
/// UIKit `Task {}` in a scene delegate, so a UIKit app needs no wrapper.
public enum SYSBootstrap {
    /// How long to wait for fresh config before deciding the gates.
    ///
    /// Config normally applies next launch, so the app stays stable mid-session.
    /// The gates are the exception: a kill switch that needs a relaunch is not a
    /// kill switch. So startup gives the network a brief chance, then proceeds
    /// on cached config regardless — an offline launch is never blocked.
    public static var gateRefreshTimeout: TimeInterval = 2.5

    /// - Parameters:
    ///   - requiresAssets: true for apps that ship no content in the bundle and
    ///     cannot draw anything until the required packs are downloaded. Startup
    ///     then fails closed with `.dataUnavailable` rather than reaching a home
    ///     screen with nothing to show.
    ///   - assetProgress: called on the download's task while packs are fetched.
    ///     Hop to the main actor before touching UI.
    public static func start(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresAssets: Bool = false,
        requiresConfig: Bool = false,
        assetProgress: (@MainActor @Sendable (SYSAssetProgress) -> Void)? = nil
    ) async -> SYSAppState {
        // 1. Whatever is already on the device — instant, never fails.
        config.load()

        // 2. Record the launch before anything reads lifecycle state.
        SYSLifecycle.recordLaunch(config: config)

        // 3. Bring config up to date.
        if let blocked = await fetchConfig(config, required: requiresConfig) {
            return blocked
        }

        // 4. Gates first: they override everything else.
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

        // 5. Content the app cannot start without. After the gates, because a
        //    maintenance or force-update screen must still appear on a device
        //    that cannot download anything — those are exactly the situations
        //    where the download is likely to fail too, and the user needs the
        //    real reason rather than a generic network error.
        if requiresAssets {
            let prepared = await SYSAssets.shared.prepareRequired(progress: assetProgress)
            if case let .failure(error) = prepared {
                SYSLogger.error("startup: required content unavailable — \(error)")
                return .dataUnavailable(error)
            }
            // Pack names carry a content hash, so a republished pack lands beside
            // its predecessor. Left to each app to remember, this is the kind of
            // housekeeping that is skipped until a device fills up.
            await SYSAssets.shared.pruneStalePacks()
        }

        // 6. Onboarding before anything else the user could act on.
        if onboardingEnabled, SYSOnboarding.shouldShow {
            return .onboarding
        }

        // 7. Then release notes, once per version.
        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }

        return .ready
    }

    /// Retries the required-content download after `.dataUnavailable`.
    ///
    /// Already-cached packs are skipped, so this costs only what is still
    /// missing. Returns the state to show next — `.ready` on success, or
    /// `.dataUnavailable` again with the current reason.
    public static func retryContent(
        config: SYSConfig = .shared,
        onboardingEnabled: Bool = true,
        requiresConfig: Bool = false,
        assetProgress: (@MainActor @Sendable (SYSAssetProgress) -> Void)? = nil
    ) async -> SYSAppState {
        // Config first, same reason as `start`: if the server is in
        // maintenance, say so rather than fail the download again.
        if let blocked = await fetchConfig(config, required: requiresConfig) {
            return blocked
        }
        if SYSMaintenance.isActive(config: config) {
            return .maintenance(message: SYSMaintenance.message(config: config))
        }

        let prepared = await SYSAssets.shared.prepareRequired(progress: assetProgress)
        if case let .failure(error) = prepared { return .dataUnavailable(error) }
        if onboardingEnabled, SYSOnboarding.shouldShow { return .onboarding }
        return resume(config: config)
    }

    /// Continues after the app dismisses onboarding or what's-new.
    ///
    /// Kept separate so the app decides when its screen is finished rather than
    /// this guessing.
    public static func resume(config: SYSConfig = .shared) -> SYSAppState {
        if SYSOnboarding.shouldShow { return .onboarding }
        if SYSWhatsNew.shouldShow(config: config), let notes = SYSWhatsNew.notes(config: config) {
            return .whatsNew(notes)
        }
        return .ready
    }

    /// Brings config up to date, and says whether the launch has to stop.
    ///
    /// An app that ships a config, or has fetched one before, only wants the
    /// gates freshened — raced against a short timeout, failure ignored,
    /// since offline with yesterday's config is a working app. An app that
    /// ships nothing and has never fetched has no config at all, so a
    /// failure stops the launch with the same blocker as missing content.
    ///
    /// - Returns: the state to show instead, or nil to carry on.
    private static func fetchConfig(_ config: SYSConfig, required: Bool) async -> SYSAppState? {
        guard required, !config.hasLocalCopy else {
            await refreshWithTimeout(config: config)
            return nil
        }

        // No timeout race here. The launch cannot proceed without this, so
        // abandoning the fetch early would only reach the failure sooner —
        // `SYSNetwork` already bounds how long a request may take.
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
            // Whichever finishes first wins; the other is abandoned.
            await group.next()
            group.cancelAll()
        }
    }
}
