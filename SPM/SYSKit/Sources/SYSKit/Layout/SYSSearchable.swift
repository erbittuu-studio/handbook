#if os(iOS)
import SwiftUI

public extension View {
    @ViewBuilder
    func sysSearchable(text: Binding<String>, prompt: String) -> some View {
        if #available(iOS 26.0, *) {
            searchable(text: text, prompt: prompt)
        } else {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
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
