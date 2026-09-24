#if canImport(UserNotifications) && !os(watchOS)
import UserNotifications

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

    private override init() {}

    /// Registers this as `UNUserNotificationCenterDelegate`. Call once at
    /// launch, before anything schedules a request.
    public func install() {
        UNUserNotificationCenter.current().delegate = self
    }

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

extension SYSNotifications: UNUserNotificationCenterDelegate {
    /// Shows the banner even while the app is foregrounded. Every existing
    /// scheduler in this portfolio wants that; nobody has needed
    /// per-notification-type control of it yet.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        onTap?(response.notification.request.content.userInfo)
    }
}
#endif
