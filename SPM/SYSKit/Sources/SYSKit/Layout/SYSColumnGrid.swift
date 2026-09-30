#if os(iOS)
import SwiftUI

public struct SYSColumnGrid<Content: View>: View {
    private let minimumWidth: CGFloat
    private let spacing: CGFloat
    private let content: Content

    public init(
        minimumWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing, alignment: .top)],
            spacing: spacing
        ) {
            content
        }
    }
}
#endif
