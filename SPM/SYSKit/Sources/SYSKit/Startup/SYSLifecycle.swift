import Foundation

/// Launch and install tracking.
public enum SYSLifecycle {
    private static let installDateKey = SYSSettingsKey<Date?>("sys.lifecycle.installDate", default: nil)
    private static let launchCountKey = SYSSettingsKey<Int>("sys.lifecycle.launchCount", default: 0)
    private static let lastVersionKey = SYSSettingsKey<String?>("sys.lifecycle.lastVersion", default: nil)

    static var isFirstLaunch: Bool { record.value.isFirstLaunch }
    static var isFirstLaunchAfterUpdate: Bool { record.value.isFirstLaunchAfterUpdate }
    static var previousVersion: String? { record.value.previousVersion }

    private struct Record {
        var isFirstLaunch = false
        var isFirstLaunchAfterUpdate = false
        var previousVersion: String?
    }

    private static let record = SYSLocked(Record())

    static func recordLaunch(config: SYSConfig = .shared) {
        let settings = SYSSettings.shared
        let current = config.currentVersion

        let isFirst = settings[installDateKey] == nil
        if isFirst {
            settings[installDateKey] = Date()
        }

        let previous = settings[lastVersionKey]
        record.value = Record(
            isFirstLaunch: isFirst,
            isFirstLaunchAfterUpdate: previous != nil && previous != current,
            previousVersion: previous
        )

        settings[launchCountKey] += 1
        settings[lastVersionKey] = current
    }

    public static var launchCount: Int { SYSSettings.shared[launchCountKey] }

    static var installDate: Date { SYSSettings.shared[installDateKey] ?? Date() }

    static var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
    }

    static func reset() {
        let settings = SYSSettings.shared
        settings.remove(installDateKey)
        settings.remove(launchCountKey)
        settings.remove(lastVersionKey)
        record.value = Record()
    }
}

/// Versioned onboarding.
public enum SYSOnboarding {
    private static let seenKey = SYSSettingsKey<Int>("sys.onboarding.seenVersion", default: 0)

    static var currentVersion: Int {
        get { version.value }
        set { version.value = newValue }
    }

    private static let version = SYSLocked(1)

    static var shouldShow: Bool { SYSSettings.shared[seenKey] < currentVersion }

    public static func markSeen() { SYSSettings.shared[seenKey] = currentVersion }

    static func reset() { SYSSettings.shared.remove(seenKey) }
}
