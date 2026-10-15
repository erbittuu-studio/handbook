#if os(iOS)
import SwiftUI

private struct SYSLeadingTitle<Label: View>: ViewModifier {
    let title: String
    let label: Label

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarRole(.browser)
                .toolbar {
                    ToolbarItem(placement: .title) {
                        label
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

public extension View {
    /// Shows the screen's title beside the back button, the way a browser does; `font` and `color` style the text.
    func sysNavigationTitle(
        _ title: String,
        font: Font = SYSFont.rounded.largeTitle.weight(.bold),
        color: Color? = nil
    ) -> some View {
        modifier(SYSLeadingTitle(title: title, label: Text(title).font(font).foregroundColor(color)))
    }

    /// Shows a title built by the app, such as a symbol with gradient text, in the same place; `title` still names the screen for the system.
    func sysNavigationTitle<Label: View>(_ title: String, @ViewBuilder label: () -> Label) -> some View {
        modifier(SYSLeadingTitle(title: title, label: label()))
    }
}
#endif
