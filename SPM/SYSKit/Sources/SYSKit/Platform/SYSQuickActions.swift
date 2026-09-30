#if canImport(UIKit) && !os(watchOS)
import UIKit

/// One Home Screen quick action.
///
/// `id` is the app's own reverse-DNS-flavoured string (e.g.
/// `"com.app.quickaction.today"`) — it round-trips through both entry points
/// below and is what the app switches on to decide what happened. SYSKit has
/// no opinion on what an id means; that is the whole of what stays app-owned.
public struct SYSQuickAction: Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImageName: String?

    public init(id: String, title: String, subtitle: String? = nil, systemImageName: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
    }
}

/// Registers dynamic Home Screen shortcuts and extracts which one fired,
/// identically from a cold launch and from a tap while already running.
///
/// Building a `UIApplicationShortcutItem` and reading one back out are both
/// one-liners — the actual bug is elsewhere. `application(_:performActionFor:)`
/// fires while the app is already on screen, so a shortcut tapped there can
/// act immediately; the launch-options case fires before anything has
/// appeared, so acting on it immediately reaches a view that is not there
/// yet. That is a `SYSPendingIntent`'s job, not this type's — this only gets
/// both cases down to the same `String` id, so the app writes the "was it
/// safe to act now" decision once, not twice with two different answers.
public enum SYSQuickActions {
    /// Replaces the app's dynamic shortcut set. Call whenever the set could
    /// have changed — a language switch, content becoming available — not
    /// only at launch; static shortcuts are never touched.
    @MainActor
    public static func register(_ actions: [SYSQuickAction]) {
        UIApplication.shared.shortcutItems = actions.map { action in
            var icon: UIApplicationShortcutIcon?
            if let systemImageName = action.systemImageName {
                icon = UIApplicationShortcutIcon(systemImageName: systemImageName)
            }
            return UIApplicationShortcutItem(
                type: action.id,
                localizedTitle: action.title,
                localizedSubtitle: action.subtitle,
                icon: icon
            )
        }
    }

    /// Call from `application(_:didFinishLaunchingWithOptions:)`. Nil unless
    /// the launch itself came from a shortcut.
    public static func coldLaunchActionID(
        _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> String? {
        (launchOptions?[.shortcutItem] as? UIApplicationShortcutItem)?.type
    }

    /// Call from `application(_:performActionFor:completionHandler:)`.
    public static func actionID(from shortcutItem: UIApplicationShortcutItem) -> String {
        shortcutItem.type
    }
}
#endif
