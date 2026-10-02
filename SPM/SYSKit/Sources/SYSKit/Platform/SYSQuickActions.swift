#if canImport(UIKit) && !os(watchOS)
import UIKit

/// One Home Screen quick action.
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

/// Registers dynamic Home Screen shortcuts and extracts which one fired, identically from a cold launch and from a tap w...
public enum SYSQuickActions {
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

    public static func coldLaunchActionID(
        _ launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> String? {
        (launchOptions?[.shortcutItem] as? UIApplicationShortcutItem)?.type
    }

    public static func actionID(from shortcutItem: UIApplicationShortcutItem) -> String {
        shortcutItem.type
    }
}
#endif
