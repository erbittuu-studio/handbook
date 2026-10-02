#if canImport(StoreKit) && canImport(UIKit) && !os(watchOS)
import StoreKit
import UIKit

/// Presents the system review prompt, but only when SYSRating says it is due.
public enum SYSReview {
    @MainActor
    @discardableResult
    public static func askIfDue() -> Bool {
        askIfDue(config: .shared)
    }

    @MainActor
    @discardableResult
    static func askIfDue(config: SYSConfig) -> Bool {
        guard SYSRating.shouldAsk(config: config) else { return false }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            SYSLogger.info("review: due, but no active scene — not asking")
            return false
        }

        SKStoreReviewController.requestReview(in: scene)
        SYSRating.markAsked(config: config)
        SYSLogger.info("review: prompt requested")
        return true
    }
}
#endif
