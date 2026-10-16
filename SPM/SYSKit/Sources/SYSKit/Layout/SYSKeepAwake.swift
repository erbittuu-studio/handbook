#if os(iOS)
import SwiftUI
import UIKit

private struct SYSKeepAwake: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

public extension View {
    /// Stops the screen from locking while this view is shown, for a screen someone uses without touching it much, such as a counter.
    func sysKeepsScreenAwake() -> some View {
        modifier(SYSKeepAwake())
    }
}
#endif
