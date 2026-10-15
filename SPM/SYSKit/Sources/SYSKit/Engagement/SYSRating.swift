import Foundation

enum SYSRating {
    private static let lastAskedVersionKey = SYSSettingsKey<String?>("sys.rating.lastAskedVersion", default: nil)

    static func shouldAsk(config: SYSConfig = .shared) -> Bool {
        guard config.flag("showRatingPrompt", default: true) else { return false }
        guard SYSSettings.shared[lastAskedVersionKey] != config.currentVersion else { return false }

        let minSessions = config.data.rating?.minSessions ?? 0
        let minDays = config.data.rating?.minDaysSinceInstall ?? 0

        guard SYSLifecycle.launchCount >= minSessions else { return false }
        guard SYSLifecycle.daysSinceInstall >= minDays else { return false }
        return true
    }

    static func markAsked(config: SYSConfig = .shared) {
        SYSSettings.shared[lastAskedVersionKey] = config.currentVersion
    }

    static func reset() {
        SYSSettings.shared.remove(lastAskedVersionKey)
    }
}
