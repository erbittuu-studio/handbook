#if os(iOS)
import SwiftUI

public extension View {
    func sysSearchable(text: Binding<String>, prompt: String, focusOnAppear: Bool = false) -> some View {
        modifier(SYSSearchable(text: text, prompt: prompt, focusOnAppear: focusOnAppear))
    }
}

private struct SYSSearchable: ViewModifier {
    @Binding var text: String
    let prompt: String
    let focusOnAppear: Bool
    @FocusState private var isFocused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .searchable(text: $text, prompt: prompt)
                .searchFocused($isFocused)
                .onAppear {
                    if focusOnAppear { isFocused = true }
                }
        } else {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        }
    }
}

@available(iOS 18.0, *)
public extension TabRole {
    static var sysSearch: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
    }
}
#endif
