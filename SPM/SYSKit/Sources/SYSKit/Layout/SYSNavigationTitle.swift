#if os(iOS)
import SwiftUI

private struct SYSLeadingTitle: ViewModifier {
    let title: String
    let font: Font

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarRole(.browser)
                .toolbar {
                    ToolbarItem(placement: .title) {
                        Text(title)
                            .font(font)
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
    func sysNavigationTitle(_ title: String, font: Font = SYSFont.rounded.largeTitle.weight(.bold)) -> some View {
        modifier(SYSLeadingTitle(title: title, font: font))
    }
}
#endif
