import Foundation

/// The words in the update reminder. SYSKit carries translations (`forLanguages`); an app may pass its own text.
public struct SYSUpdateReminderText: Sendable {
    public var title: String
    public var message: String
    public var update: String
    public var skip: String

    public init(
        title: String = "Update available",
        message: String = "A newer version is out with improvements and fixes.",
        update: String = "Update",
        skip: String = "Skip this version"
    ) {
        self.title = title
        self.message = message
        self.update = update
        self.skip = skip
    }
}

/// Offers the update the remote config recommends: Update opens the App Store, Skip stops asking for that version.
public enum SYSUpdateReminder {
    static let skippedKey = SYSSettingsKey<String?>("sys.update.skippedVersion", default: nil)

    static func pending(config: SYSConfig, settings: SYSSettings = .shared) -> SYSRecommendedUpdate? {
        guard let update = SYSUpdate.recommended(config: config),
              settings[skippedKey] != update.version
        else { return nil }
        return update
    }
}

#if canImport(UIKit) && !os(watchOS)
import UIKit

extension SYSUpdateReminder {
    @MainActor private static var shownThisLaunch = false

    /// Shows the reminder when one is due, at most once per launch. `open` receives the App Store URL; a Kids Category app passes it through its parental gate.
    @MainActor
    @discardableResult
    public static func showIfDue(text: SYSUpdateReminderText = .forLanguages(), open: ((URL) -> Void)? = nil) -> Bool {
        showIfDue(config: .shared, text: text, open: open)
    }

    @MainActor
    static func showIfDue(config: SYSConfig, text: SYSUpdateReminderText, open: ((URL) -> Void)?) -> Bool {
        guard !shownThisLaunch, let update = pending(config: config), let presenter = topViewController() else { return false }

        let alert = UIAlertController(title: text.title, message: update.message ?? text.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text.update, style: .default) { _ in
            guard let url = SYSAppStore.url() else { return }
            if let open { open(url) } else { UIApplication.shared.open(url) }
        })
        alert.addAction(UIAlertAction(title: text.skip, style: .cancel) { _ in
            SYSSettings.shared[skippedKey] = update.version
        })
        presenter.present(alert, animated: true)
        shownThisLaunch = true
        SYSLogger.info("update: reminder shown for \(update.version)")
        return true
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            var top = scene.keyWindow?.rootViewController
        else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
