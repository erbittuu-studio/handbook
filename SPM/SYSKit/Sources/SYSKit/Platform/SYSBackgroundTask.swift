#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Runs non-blocking startup work under an iOS background task assertion, so something started just before the app is ba...
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
