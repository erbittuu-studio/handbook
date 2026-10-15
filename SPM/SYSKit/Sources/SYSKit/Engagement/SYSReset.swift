import Foundation
import UserNotifications
#if os(iOS)
import CoreSpotlight
import UIKit
#endif

public extension Notification.Name {
    /// Posted after a reset has erased everything. An object that keeps a copy of stored values in memory reloads them on this.
    static let sysDidReset = Notification.Name("SYSDidReset")
}

/// Puts the app back to how it was on the day it was installed.
public enum SYSReset {
    /// Erases everything the app stored: every setting, file, cache, download, notification and search entry, and what SYSKit
    /// keeps in memory. Pass the app group identifiers the app shares data through, so a widget or Watch app is cleared too.
    @MainActor
    public static func eraseEverything(appGroups: [String] = []) async {
        SYSResetRegistry.resetAll()
        SYSAppCatalog.shared.resetForFreshInstall()
        SYSSpeech.shared.resetForFreshInstall()

        eraseSettings(appGroups: appGroups)
        eraseFiles(appGroups: appGroups)
        eraseSystemState()

        SYSLogFile.shared.reopenAfterErase()
        NotificationCenter.default.post(name: .sysDidReset, object: nil)
    }

    /// Erases everything, then starts the launch sequence again: splash, then the first-run flow, like a fresh install.
    @MainActor
    public static func resetApp(appGroups: [String] = []) async {
        await eraseEverything(appGroups: appGroups)
        SYSStartup.current?.restart()
    }

    @MainActor
    private static func eraseSettings(appGroups: [String]) {
        let standard = UserDefaults.standard
        if let identifier = Bundle.main.bundleIdentifier {
            standard.removePersistentDomain(forName: identifier)
        }
        for key in standard.dictionaryRepresentation().keys where isOwnKey(key) {
            standard.removeObject(forKey: key)
        }
        standard.synchronize()
        for group in appGroups {
            guard let shared = UserDefaults(suiteName: group) else { continue }
            shared.removePersistentDomain(forName: group)
            for key in shared.dictionaryRepresentation().keys where isOwnKey(key) { shared.removeObject(forKey: key) }
            shared.synchronize()
        }
    }

    private static func isOwnKey(_ key: String) -> Bool {
        !(key.hasPrefix("NS") || key.hasPrefix("Apple") || key.hasPrefix("AK") || key.hasPrefix("com.apple."))
    }

    @MainActor
    private static func eraseFiles(appGroups: [String]) {
        let manager = FileManager.default
        for url in manager.urls(for: .documentDirectory, in: .userDomainMask) { removeContents(of: url) }
        for library in manager.urls(for: .libraryDirectory, in: .userDomainMask) {
            removeContents(of: library, keeping: ["Preferences"])
        }
        removeContents(of: manager.temporaryDirectory)
        for group in appGroups {
            if let container = manager.containerURL(forSecurityApplicationGroupIdentifier: group) {
                removeContents(of: container)
            }
        }
    }

    @MainActor
    private static func eraseSystemState() {
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        #if os(iOS)
        SYSNotifications.shared.clearBadge()
        UIApplication.shared.shortcutItems = []
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
        #endif
    }

    static func removeContents(of directory: URL, keeping kept: Set<String> = []) {
        let manager = FileManager.default
        let listed = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
        guard let items = listed else { return }
        for item in items where !kept.contains(item.lastPathComponent) {
            try? manager.removeItem(at: item)
        }
    }
}
