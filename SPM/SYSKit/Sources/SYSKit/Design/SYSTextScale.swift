#if os(iOS)
import SwiftUI

private struct SYSRegularWidthText: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let steps: Int
    let largest: DynamicTypeSize

    func body(content: Content) -> some View {
        content.transformEnvironment(\.dynamicTypeSize) { size in
            let sizes = DynamicTypeSize.allCases
            let boost = horizontalSizeClass == .regular ? steps : 0
            let index = (sizes.firstIndex(of: size) ?? 0) + boost
            let limit = sizes.firstIndex(of: largest) ?? sizes.count - 1
            size = sizes[min(index, limit)]
        }
    }
}

public extension View {
    func sysRegularWidthText(steps: Int = 2, largest: DynamicTypeSize = .accessibility1) -> some View {
        modifier(SYSRegularWidthText(steps: steps, largest: largest))
    }
}
#endif
