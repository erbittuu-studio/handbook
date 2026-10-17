#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// The things an app may ask of the person once per launch: install an update, allow reminders, and try another of our apps.
///
/// They appear only on the dashboard (the view that carries `.sysDashboardPrompts`), only when nothing is presented over it,
/// and one after the other, so they never stack and never appear on a lesson, a canvas or the first-run flow.
/// Leaving the dashboard stops the wait; coming back starts it again. Each runs at most once per launch.
@MainActor
enum SYSDashboardPrompts {
    private(set) static var finished = false
    private static var launchCounted = false

    static func run(
        text: SYSUpdateReminderText,
        open: ((URL) -> Void)?,
        notifications: SYSNotificationPrompt?,
        suggestion: (style: SYSAppSuggestionStyle, text: SYSAppSuggestionText)?
    ) async {
        guard !finished else { return }
        if suggestion != nil, !launchCounted {
            launchCounted = true
            SYSAppSuggestion.recordOpen()
        }
        guard await settle(SYSTiming.relaxed * 3) else { return }

        let shown = await withCheckedContinuation { continuation in
            if !SYSUpdateReminder.showIfDue(text: text, open: open, onFinish: { continuation.resume(returning: true) }) {
                continuation.resume(returning: false)
            }
        }
        if shown, !(await settle(SYSTiming.relaxed)) { return }

        let asked = await notifications?.askIfDue() ?? false
        if let suggestion, !shown, !asked, await settle(SYSTiming.relaxed) {
            SYSAppSuggestion.showIfDue(style: suggestion.style, text: suggestion.text)
        }
        finished = true
    }

    /// Coming back to the dashboard after a while away is another open; the launch run has already finished by then.
    static func suggestOnReturn(_ suggestion: (style: SYSAppSuggestionStyle, text: SYSAppSuggestionText)) async {
        guard finished else { return }
        SYSAppSuggestion.recordOpen()
        guard await settle(SYSTiming.relaxed * 2) else { return }
        SYSAppSuggestion.showIfDue(style: suggestion.style, text: suggestion.text)
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
    let suggestion: (style: SYSAppSuggestionStyle, text: SYSAppSuggestionText)?
    @State private var job: Task<Void, Never>?
    @State private var visible = false
    @State private var leftAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                visible = true
                job?.cancel()
                job = Task {
                    await SYSDashboardPrompts.run(text: text, open: open, notifications: notifications, suggestion: suggestion)
                }
            }
            .onDisappear {
                visible = false
                job?.cancel()
                job = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                leftAt = Date()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                returned()
            }
    }

    private func returned() {
        guard visible, let suggestion, let leftAt else { return }
        guard Date().timeIntervalSince(leftAt) > SYSAppSuggestionPolicy.awayForAnOpen else { return }
        self.leftAt = nil
        job?.cancel()
        job = Task { await SYSDashboardPrompts.suggestOnReturn(suggestion) }
    }
}

extension View {
    /// Shows the update reminder, then asks for notification permission, then suggests another app on a fixed
    /// sequence of opens, on this dashboard only.
    /// - `open`: receives the App Store URL; a Kids Category app routes it through its parental gate.
    /// - `notifications`: the permission prompt, shown after the update reminder when it is due.
    /// - `suggestion`: when given, the app suggestion popup may follow, in these colors and words;
    ///   `suggestionText` takes the app's own language.
    public func sysDashboardPrompts(
        text: SYSUpdateReminderText = .forLanguages(),
        open: ((URL) -> Void)? = nil,
        notifications: SYSNotificationPrompt? = nil,
        suggestion: SYSAppSuggestionStyle? = nil,
        suggestionText: SYSAppSuggestionText = .forLanguages()
    ) -> some View {
        modifier(SYSDashboardPromptsModifier(
            text: text,
            open: open,
            notifications: notifications,
            suggestion: suggestion.map { ($0, suggestionText) }
        ))
    }
}
#endif
