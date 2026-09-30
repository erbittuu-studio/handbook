#if os(iOS)
import SwiftUI

public struct SYSNavigationContainer<Content: View>: View {
    private let tint: Color
    private let content: Content

    public init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
                .tint(tint)
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
                .tint(tint)
        }
    }
}
#endif
