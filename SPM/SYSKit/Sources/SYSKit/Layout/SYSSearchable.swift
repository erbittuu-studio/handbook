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
#endif
