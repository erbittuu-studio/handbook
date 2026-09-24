import Foundation

/// Launch and install tracking.
///
/// Small, but several features depend on it: the rating rules in config
/// (`minSessions`, `minDaysSinceInstall`) are inert without it, and
/// "what's new" needs to know an update just happened.
public enum SYSLifecycle {
    private static let installDateKey = SYSSettingsKey<Date?>("sys.lifecycle.installDate", default: nil)
    private static let launchCountKey = SYSSettingsKey<Int>("sys.lifecycle.launchCount", default: 0)
    private static let lastVersionKey = SYSSettingsKey<String?>("sys.lifecycle.lastVersion", default: nil)

    public private(set) static var isFirstLaunch = false
    public private(set) static var isFirstLaunchAfterUpdate = false
    public private(set) static var previousVersion: String?

    /// Call once at launch, before reading anything else here.
    ///
    /// Note this means first launch of this *install*, not first ever: settings
    /// come back with an iCloud restore, so a new phone is not a fresh install.
    /// That is usually what you want.
    public static func recordLaunch(config: SYSConfig = .shared) {
        let settings = SYSSettings.shared
        let current = config.currentVersion

        if settings[installDateKey] == nil {
            settings[installDateKey] = Date()
            isFirstLaunch = true
        }

        previousVersion = settings[lastVersionKey]
        isFirstLaunchAfterUpdate = previousVersion != nil && previousVersion != current

        settings[launchCountKey] += 1
        settings[lastVersionKey] = current
    }

    public static var launchCount: Int { SYSSettings.shared[launchCountKey] }

    public static var installDate: Date { SYSSettings.shared[installDateKey] ?? Date() }

    public static var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    /// Test hook — resets the recorded state.
    public static func reset() {
        let settings = SYSSettings.shared
        settings.remove(installDateKey)
        settings.remove(launchCountKey)
        settings.remove(lastVersionKey)
        isFirstLaunch = false
        isFirstLaunchAfterUpdate = false
        previousVersion = nil
    }
}

/// Versioned onboarding.
///
/// A boolean "has seen onboarding" cannot re-show a *new* flow later — everyone
/// is already marked as done, and you end up with `hasSeenOnboarding2`. Storing
/// which version was seen means bumping a number brings it back for everyone.
public enum SYSOnboarding {
    private static let seenKey = SYSSettingsKey<Int>("sys.onboarding.seenVersion", default: 0)

    /// Bump when the flow changes materially.
    public static var currentVersion = 1

    public static var shouldShow: Bool { SYSSettings.shared[seenKey] < currentVersion }

    public static func markSeen() { SYSSettings.shared[seenKey] = currentVersion }

    public static func reset() { SYSSettings.shared.remove(seenKey) }
}
