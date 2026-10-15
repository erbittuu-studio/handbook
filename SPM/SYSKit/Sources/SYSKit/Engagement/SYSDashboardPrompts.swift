#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// The two things an app may ask of the person once per launch: install an update, and allow reminders.
///
/// They appear only on the dashboard (the view that carries `.sysDashboardPrompts`), only when nothing is presented over it,
/// and one after the other, so they never stack and never appear on a lesson, a canvas or the first-run flow.
/// Leaving the dashboard stops the wait; coming back starts it again. Each runs at most once per launch.
@MainActor
enum SYSDashboardPrompts {
    private static var finished = false

    static func run(text: SYSUpdateReminderText, open: ((URL) -> Void)?, notifications: SYSNotificationPrompt?) async {
        guard !finished else { return }
        guard await settle(SYSTiming.relaxed * 3) else { return }

        let shown = await withCheckedContinuation { continuation in
            if !SYSUpdateReminder.showIfDue(text: text, open: open, onFinish: { continuation.resume(returning: true) }) {
                continuation.resume(returning: false)
            }
        }
        if shown, !(await settle(SYSTiming.relaxed)) { return }

        await notifications?.askIfDue()
        finished = true
    }

    private static func settle(_ delay: TimeInterval) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        while SYSUpdateReminder.hasPresentedScreen() || UIApplication.shared.applicationState != .active {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return !Task.isCancelled
    }
}

private struct SYSDashboardPromptsModifier: ViewModifier {
    let text: SYSUpdateReminderText
    let open: ((URL) -> Void)?
    let notifications: SYSNotificationPrompt?
    @State private var job: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                job?.cancel()
                job = Task { await SYSDashboardPrompts.run(text: text, open: open, notifications: notifications) }
            }
            .onDisappear {
                job?.cancel()
                job = nil
            }
    }
}

extension View {
    /// Shows the update reminder, then asks for notification permission, on this dashboard only.
    /// - `open`: receives the App Store URL; a Kids Category app routes it through its parental gate.
    /// - `notifications`: the permission prompt, shown after the update reminder when it is due.
    public func sysDashboardPrompts(
        text: SYSUpdateReminderText = .forLanguages(),
        open: ((URL) -> Void)? = nil,
        notifications: SYSNotificationPrompt? = nil
    ) -> some View {
        modifier(SYSDashboardPromptsModifier(text: text, open: open, notifications: notifications))
    }
}
#endif
