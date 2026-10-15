#if os(iOS)
import SwiftUI

/// The Settings section every app shares for resetting: one row that opens the reset screen in a sheet.
public struct SYSResetSection: View {
    private let title: String
    private let row: String
    private let close: String
    private let tint: Color
    private let text: SYSResetText
    private let style: SYSResetStyle
    private let appGroups: [String]
    private let onReset: () async -> Void

    @State private var showing = false

    public init(
        title: String,
        row: String,
        close: String,
        tint: Color,
        text: SYSResetText,
        style: SYSResetStyle,
        appGroups: [String] = [],
        onReset: @escaping () async -> Void = {}
    ) {
        self.title = title
        self.row = row
        self.close = close
        self.tint = tint
        self.text = text
        self.style = style
        self.appGroups = appGroups
        self.onReset = onReset
    }

    public var body: some View {
        SYSSettingsSection(title) {
            SYSSettingsRow(icon: SYSSymbol.replay, tint: tint, title: row, chevron: SYSSymbol.chevronForward) {
                SYSHaptics.light()
                showing = true
            } trailing: { EmptyView() }
        }
        .sheet(isPresented: $showing) {
            SYSNavigationContainer(title: text.title, trailing: .close(close) { showing = false }) {
                SYSResetScreen(text: text, style: style) {
                    Task {
                        await onReset()
                        await SYSReset.resetApp(appGroups: appGroups)
                    }
                }
            }
            .modifier(SYSNoSwipeDismiss())
        }
    }
}

private struct SYSNoSwipeDismiss: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.interactiveDismissDisabled(true)
        } else {
            content
        }
    }
}
#endif
