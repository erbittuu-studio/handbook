#if os(iOS)
import SwiftUI

private struct SYSLaunchHandoff: ViewModifier {
    let color: Color

    @State private var covered = true

    func body(content: Content) -> some View {
        content
            .overlay {
                color
                    .ignoresSafeArea()
                    .opacity(covered ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear {
                withAnimation(.easeOut(duration: SYSTiming.relaxed)) { covered = false }
            }
    }
}

extension View {
    /// Starts the splash on the flat colour of the system launch screen (the `LaunchBackground` colour every app declares)
    /// and fades it away, so the hand-off never jumps, whatever theme or appearance the splash then shows.
    func sysLaunchHandoff(_ color: Color) -> some View {
        modifier(SYSLaunchHandoff(color: color))
    }
}
#endif
