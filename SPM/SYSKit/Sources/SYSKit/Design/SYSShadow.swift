#if os(iOS)
import SwiftUI

public struct SYSShadow: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    public static let text = SYSShadow(color: .black.opacity(0.18), radius: 4, y: 2)
    public static let xs = SYSShadow(color: .black.opacity(0.06), radius: 4, y: 1)
    public static let card = SYSShadow(color: .black.opacity(0.07), radius: 10, y: 2)
    public static let raised = SYSShadow(color: .black.opacity(0.10), radius: 16, y: 4)
}

public extension View {
    func sysShadow(_ shadow: SYSShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
#endif
