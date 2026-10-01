#if canImport(UserNotifications) && !os(watchOS)
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Permission, scheduling and tap-routing for local notifications — not
/// scheduling *policy*. Two apps here each built a real notification system
/// (a 64-slot iOS-wide budget split across categories in one, a fixed weekly
/// cadence in the other) and that domain logic is genuinely theirs; what was
/// actually identical between them was asking for permission, remembering
/// that it asked, presenting a notification while foregrounded, and routing
/// a tap onward — all four now live here once, so an app schedules through
/// `schedule`/`cancel` and keeps its own reasons for what and when.
@MainActor
public final class SYSNotifications: NSObject {
    public static let shared = SYSNotifications()

    private static let askedKey = SYSSettingsKey<Bool>("sys_notifications_asked", default: false)

    /// Whether this app has ever asked for notification permission. Answers
    /// "have we asked", not "did the user say yes" — check
    /// `authorizationStatus()` for that.
    public static var hasAskedPermission: Bool {
        SYSSettings.shared[askedKey]
    }

    /// Called with a tapped notification's `userInfo`. The app reads
    /// whatever it put there and feeds its own `SYSPendingIntent`.
    public var onTap: (([AnyHashable: Any]) -> Void)?

    /// How many local notifications iOS keeps pending for one app; anything
    /// scheduled beyond it is silently dropped.
    public static let pendingLimit = 64

    private override init() {}

    /// Registers this as `UNUserNotificationCenterDelegate`. Call once at
    /// launch, before anything schedules a request.
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

    /// Requests permission, and records that it asked regardless of the
    /// answer — the record is what stops an app asking again unprompted,
    /// which the system itself only allows once per install anyway.
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

    /// Whether anything scheduled will actually be delivered: allowed outright
    /// or provisionally.
    public var isAuthorized: Bool {
        get async {
            switch await authorizationStatus() {
            case .authorized, .provisional, .ephemeral: return true
            default: return false
            }
        }
    }

    #if canImport(UIKit)
    /// Opens this app's page in Settings, where a denied permission can be
    /// turned back on.
    public func openSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }
    #endif

    public func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    /// Schedules one request, replacing anything already scheduled under the
    /// same id.
    public func schedule(id: String, trigger: UNNotificationTrigger?, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Task { @MainActor in SYSLogger.error("notifications: schedule failed for \(id)", error) }
            }
        }
    }

    /// Schedules a request that repeats whenever `components` match — daily
    /// at a time, or weekly when a weekday is included.
    public func scheduleRepeating(id: String, matching components: DateComponents, content: UNMutableNotificationContent) {
        schedule(id: id, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true), content: content)
    }

    /// Rebuilds one family of requests: cancels everything under `prefix`,
    /// then schedules `plan` earliest first, as many as still fit under
    /// `pendingLimit` after the requests that are not in this family and
    /// `reserved` slots kept free. Does nothing without permission.
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

    /// Cancels every pending request whose id starts with `idPrefix` — the
    /// shape both existing schedulers actually need: clear a whole category
    /// (`"festival_"`, `"kl_weekday_"`) before rebuilding it, without also
    /// knowing every id in it up front.
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
    public let fireDate: Date
    public let components: DateComponents
    public let content: UNMutableNotificationContent

    public init(id: String, fireDate: Date, components: DateComponents, content: UNMutableNotificationContent) {
        self.id = id
        self.fireDate = fireDate
        self.components = components
        self.content = content
    }
}

extension SYSNotifications: UNUserNotificationCenterDelegate {
    /// Shows the banner even while the app is foregrounded. Every existing
    /// scheduler in this portfolio wants that; nobody has needed
    /// per-notification-type control of it yet.
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
