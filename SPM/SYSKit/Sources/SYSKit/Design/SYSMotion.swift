#if os(iOS)
import SwiftUI

public enum SYSMotion {
    public static let press: Animation = {
        if #available(iOS 17.0, *) { return .snappy(duration: 0.25) }
        return .spring(response: 0.25, dampingFraction: 0.75)
    }()

    public static let standard: Animation = {
        if #available(iOS 17.0, *) { return .smooth(duration: 0.4) }
        return .spring(response: 0.4, dampingFraction: 0.9)
    }()

    public static let bounce: Animation = {
        if #available(iOS 17.0, *) { return .bouncy(duration: 0.55) }
        return .spring(response: 0.55, dampingFraction: 0.7)
    }()

    public static let pageTurn: Animation = {
        if #available(iOS 17.0, *) { return .snappy(duration: 0.38) }
        return .spring(response: 0.38, dampingFraction: 0.85)
    }()

    public static let floatLoop = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}
#endif
