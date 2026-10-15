#if os(iOS)
import SwiftUI

public struct SYSPressStyle: ButtonStyle {
    public enum Strength {
        case subtle
        case strong

        var scale: CGFloat {
            switch self {
            case .subtle: return 0.97
            case .strong: return 0.95
            }
        }
    }

    private let strength: Strength

    public init(_ strength: Strength = .subtle) {
        self.strength = strength
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? strength.scale : 1)
            .animation(SYSMotion.press, value: configuration.isPressed)
    }
}
#endif
