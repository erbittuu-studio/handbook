import Foundation

/// Decides when to ask for a review.
///
/// Apple silently ignores review requests beyond three per year, so asking at a
/// bad moment doesn't just fail — it burns one of the few chances you get. The
/// thresholds live in config (`rating.minSessions`, `rating.minDaysSinceInstall`)
/// so they can be tuned without shipping a build.
///
/// This decides *whether*; presenting is the app's job, since only the app knows
/// when the user is at a good moment.
public enum SYSRating {
    private static let lastAskedVersionKey = SYSSettingsKey<String?>("sys.rating.lastAskedVersion", default: nil)

    /// True when every configured threshold is met and we haven't already asked
    /// on this version.
    public static func shouldAsk(config: SYSConfig = .shared) -> Bool {
        guard config.flag("showRatingPrompt", default: true) else { return false }
        guard SYSSettings.shared[lastAskedVersionKey] != config.currentVersion else { return false }

        let minSessions = config.data.rating?.minSessions ?? 0
        let minDays = config.data.rating?.minDaysSinceInstall ?? 0

        guard SYSLifecycle.launchCount >= minSessions else { return false }
        guard SYSLifecycle.daysSinceInstall >= minDays else { return false }
        return true
    }

    /// Record that we asked, so we don't ask again on this version.
    public static func markAsked(config: SYSConfig = .shared) {
        SYSSettings.shared[lastAskedVersionKey] = config.currentVersion
    }

    public static func reset() {
        SYSSettings.shared.remove(lastAskedVersionKey)
    }
}
