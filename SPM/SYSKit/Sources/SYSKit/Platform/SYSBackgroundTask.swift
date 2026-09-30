#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Runs non-blocking startup work under an iOS background task assertion, so
/// something started just before the app is backgrounded gets the system's
/// standard grace period (roughly 30s) instead of being cut off immediately.
/// `SYSAssets`' `backgroundAssets` uses this; an app with its own background
/// work — `SYSContentSync`'s sync, say — can wrap it the same way rather than
/// inventing this per app.
public enum SYSBackgroundTask {
    #if canImport(UIKit) && !os(watchOS)
    @MainActor
    public static func run(_ name: String, _ work: @escaping () async -> Void) {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        Task {
            await work()
            if identifier != .invalid {
                await MainActor.run { UIApplication.shared.endBackgroundTask(identifier) }
            }
        }
    }
    #else
    @MainActor
    public static func run(_ name: String, _ work: @escaping () async -> Void) {
        Task { await work() }
    }
    #endif
}
