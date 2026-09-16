#if canImport(StoreKit) && canImport(UIKit) && !os(watchOS)
import StoreKit
import UIKit

/// Presents the system review prompt, but only when `SYSRating` says it is due.
///
/// `SYSRating` decides *whether*; this does the asking, which is the same eight
/// lines of StoreKit in every app plus one easy mistake: forgetting to record
/// that you asked. Apple ignores review requests beyond three a year, so an app
/// that asks without recording burns all three on the same user and then has
/// none left for anyone else. Recording is not optional, so it is not left to
/// the caller.
///
/// Call it at a good moment — a finished task, a returned-to-home — not at
/// launch. Only the app knows when that is, which is why this takes no view and
/// decides no timing beyond the thresholds in config.
public enum SYSReview {
    /// Asks if the thresholds in config are met. Does nothing otherwise.
    ///
    /// - Returns: whether the prompt was requested, mostly for logging — the
    ///   system may still decline to show anything, and there is no callback to
    ///   tell you either way.
    @MainActor
    @discardableResult
    public static func askIfDue(config: SYSConfig = .shared) -> Bool {
        guard SYSRating.shouldAsk(config: config) else { return false }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            // No active scene means no prompt would appear. Returning without
            // recording keeps the chance for the next good moment.
            SYSLogger.info("review: due, but no active scene — not asking")
            return false
        }

        SKStoreReviewController.requestReview(in: scene)
        // Recorded whether or not the system chooses to show it: from here we
        // cannot tell, and asking again on this version would be worse than
        // missing one.
        SYSRating.markAsked(config: config)
        SYSLogger.info("review: prompt requested")
        return true
    }
}
#endif
