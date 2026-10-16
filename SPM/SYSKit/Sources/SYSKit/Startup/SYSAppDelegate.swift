#if os(iOS)
import UIKit

/// The app delegate every app shares: it starts the log file and notification handling and sends Home Screen shortcuts into SYSEntries; an app subclasses it only to add its own start-up.
@MainActor
open class SYSAppDelegate: NSObject, UIApplicationDelegate {
    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        SYSLogFile.shared.install()
        SYSNotifications.shared.install()
        if let shortcutType = SYSQuickActions.coldLaunchActionID(launchOptions) {
            SYSEntries.shared.perform(shortcutType: shortcutType)
        }
        return true
    }

    open func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(SYSEntries.shared.perform(shortcutType: SYSQuickActions.actionID(from: shortcutItem)))
    }
}
#endif
