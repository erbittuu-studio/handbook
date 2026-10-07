#if canImport(UserNotifications) && !os(watchOS)
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
/// Permission, scheduling and tap-routing for local notifications — not scheduling *policy*.
public final class SYSNotifications: NSObject {
    public static let shared = SYSNotifications()

    private static let askedKey = SYSSettingsKey<Bool>("sys_notifications_asked", default: false)

    public static var hasAskedPermission: Bool {
        SYSSettings.shared[askedKey]
    }

    public var onTap: (([AnyHashable: Any]) -> Void)?

    static let pendingLimit = 64

    private override init() {}

    public func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    #if canImport(UIKit)
    public func clearBadge() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    #endif

    @discardableResult
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        SYSSettings.shared[Self.askedKey] = true
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            SYSLogger.error("notifications: permission request failed", error)
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    public var isAuthorized: Bool {
        get async {
            switch await authorizationStatus() {
            case .authorized, .provisional, .ephemeral: return true
            default: return false
            }
        }
    }

    #if canImport(UIKit)
    public func openSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }
    #endif

    func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func schedule(id: String, trigger: UNNotificationTrigger?, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in SYSLogger.error("notifications: schedule failed for \(id)", error) }
            }
        }
    }

    public func scheduleRepeating(id: String, matching components: DateComponents, content: UNMutableNotificationContent) {
        schedule(id: id, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true), content: content)
    }

    public func replaceScheduled(prefix: String, with plan: [SYSPlannedNotification], reserved: Int = 0) async {
        guard await isAuthorized else { return }
        let pending = await pendingRequests().map(\.identifier)
        let family = pending.filter { $0.hasPrefix(prefix) }
        cancel(ids: family)
        let others = pending.count - family.count
        for item in Self.withinBudget(plan, others: others, reserved: reserved) {
            schedule(
                id: item.id,
                trigger: UNCalendarNotificationTrigger(dateMatching: item.components, repeats: false),
                content: item.content
            )
        }
    }

    static func withinBudget(_ plan: [SYSPlannedNotification], others: Int, reserved: Int) -> [SYSPlannedNotification] {
        let slots = max(0, pendingLimit - reserved - others)
        return Array(plan.sorted { $0.fireDate < $1.fireDate }.prefix(slots))
    }

    public func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    public func cancel(idPrefix: String) async {
        let ids = await pendingRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) }
        guard !ids.isEmpty else { return }
        cancel(ids: ids)
    }
}

public struct SYSPlannedNotification {
    public let id: String
    let fireDate: Date
    let components: DateComponents
    public let content: UNMutableNotificationContent

    public init(id: String, fireDate: Date, components: DateComponents, content: UNMutableNotificationContent) {
        self.id = id
        self.fireDate = fireDate
        self.components = components
        self.content = content
    }
}

extension SYSNotifications: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = SYSNotificationPayload(response.notification.request.content.userInfo)
        await MainActor.run { onTap?(payload.userInfo) }
    }
}

private struct SYSNotificationPayload: @unchecked Sendable {
    let userInfo: [AnyHashable: Any]

    init(_ userInfo: [AnyHashable: Any]) {
        self.userInfo = userInfo
    }
}
#endif
