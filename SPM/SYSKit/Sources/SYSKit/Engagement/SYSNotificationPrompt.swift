#if canImport(UserNotifications) && !os(watchOS)
import UserNotifications

/// When an app asks to send reminders, and what it does with the answer.
public struct SYSNotificationPrompt {
    let minLaunch: Int
    let wanted: @MainActor () -> Bool
    let answered: @MainActor (Bool) async -> Void

    /// - `minLaunch`: ask from this launch on, so the first launches stay quiet.
    /// - `wanted`: false while the person has turned reminders off in the app.
    /// - `answered`: receives whether reminders were allowed; schedule them here.
    public init(minLaunch: Int = 3, wanted: @escaping @MainActor () -> Bool = { true }, answered: @escaping @MainActor (Bool) async -> Void) {
        self.minLaunch = minLaunch
        self.wanted = wanted
        self.answered = answered
    }

    static func isDue(launchCount: Int, minLaunch: Int, wanted: Bool, status: UNAuthorizationStatus) -> Bool {
        wanted && launchCount >= minLaunch && status == .notDetermined
    }

    /// Asks when due and returns whether it did, so the caller can keep other prompts away from this launch.
    @MainActor
    @discardableResult
    func askIfDue() async -> Bool {
        let status = await SYSNotifications.shared.authorizationStatus()
        let due = Self.isDue(launchCount: SYSLifecycle.launchCount, minLaunch: minLaunch, wanted: wanted(), status: status)
        guard due else { return false }
        await answered(await SYSNotifications.shared.requestPermission())
        return true
    }
}
#endif
