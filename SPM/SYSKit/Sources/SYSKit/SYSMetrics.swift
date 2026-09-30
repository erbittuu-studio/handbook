import CoreGraphics

public enum SYSSizeClass: Equatable, Sendable {
    case compact
    case regular
}

public struct SYSInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public static let zero = SYSInsets()

    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public var horizontal: CGFloat { leading + trailing }
    public var vertical: CGFloat { top + bottom }
}

public struct SYSMetrics: Equatable, Sendable {
    public struct Reference: Equatable, Sendable {
        public var shortSide: CGFloat
        public var longSide: CGFloat
        public var scaleRange: ClosedRange<CGFloat>

        public init(shortSide: CGFloat, longSide: CGFloat, scaleRange: ClosedRange<CGFloat> = 0.75 ... 1.7) {
            self.shortSide = shortSide
            self.longSide = longSide
            self.scaleRange = scaleRange
        }

        public static let phone = Reference(shortSide: 393, longSide: 759)
    }

    public var size: CGSize
    public var safeArea: SYSInsets
    public var horizontalClass: SYSSizeClass
    public var verticalClass: SYSSizeClass
    public var reference: Reference

    public init(
        size: CGSize,
        safeArea: SYSInsets = .zero,
        horizontalClass: SYSSizeClass = .compact,
        verticalClass: SYSSizeClass = .regular,
        reference: Reference = .phone
    ) {
        self.size = size
        self.safeArea = safeArea
        self.horizontalClass = horizontalClass
        self.verticalClass = verticalClass
        self.reference = reference
    }

    public static func atReference(_ reference: Reference = .phone) -> SYSMetrics {
        SYSMetrics(
            size: CGSize(width: reference.shortSide, height: reference.longSide),
            reference: reference
        )
    }

    public var contentSize: CGSize {
        CGSize(
            width: max(size.width - safeArea.horizontal, 1),
            height: max(size.height - safeArea.vertical, 1)
        )
    }

    public var scale: CGFloat {
        let content = contentSize
        let short = min(content.width, content.height)
        let long = max(content.width, content.height)
        let raw = min(short / reference.shortSide, long / reference.longSide)
        return min(max(raw, reference.scaleRange.lowerBound), reference.scaleRange.upperBound)
    }

    public func s(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded()
    }

    public func f(_ value: CGFloat) -> CGFloat {
        (value * (1 + (scale - 1) * 0.65)).rounded()
    }

    public var aspect: CGFloat {
        let content = contentSize
        return content.width / content.height
    }

    public var isLandscape: Bool { aspect >= 1 }
    public var isCompactWidth: Bool { horizontalClass == .compact }
    public var isCompactHeight: Bool { verticalClass == .compact }

    public func columns(minimumWidth: CGFloat, spacing: CGFloat = 0, in width: CGFloat? = nil) -> Int {
        let pitch = minimumWidth + spacing
        guard pitch > 0 else { return 1 }
        let available = width ?? contentSize.width
        return max(1, Int((available + spacing) / pitch))
    }

    public func margin(readableWidth: CGFloat, minimum: CGFloat = 0, in width: CGFloat? = nil) -> CGFloat {
        let available = width ?? contentSize.width
        return max(minimum, (available - readableWidth) / 2)
    }
}

#if os(iOS)
import SwiftUI

private struct SYSMetricsKey: EnvironmentKey {
    static let defaultValue = SYSMetrics.atReference()
}

public extension EnvironmentValues {
    var sysMetrics: SYSMetrics {
        get { self[SYSMetricsKey.self] }
        set { self[SYSMetricsKey.self] = newValue }
    }
}

private extension SYSSizeClass {
    init(_ sizeClass: UserInterfaceSizeClass?) {
        self = sizeClass == .regular ? .regular : .compact
    }
}

private struct SYSMetricsReader: ViewModifier {
    let reference: SYSMetrics.Reference

    @Environment(\.horizontalSizeClass) private var horizontalClass
    @Environment(\.verticalSizeClass) private var verticalClass

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(
                    \.sysMetrics,
                    SYSMetrics(
                        size: CGSize(
                            width: proxy.size.width + insets.leading + insets.trailing,
                            height: proxy.size.height + insets.top + insets.bottom
                        ),
                        safeArea: SYSInsets(
                            top: insets.top,
                            leading: insets.leading,
                            bottom: insets.bottom,
                            trailing: insets.trailing
                        ),
                        horizontalClass: SYSSizeClass(horizontalClass),
                        verticalClass: SYSSizeClass(verticalClass),
                        reference: reference
                    )
                )
        }
    }
}

public extension View {
    func sysMetrics(reference: SYSMetrics.Reference = .phone) -> some View {
        modifier(SYSMetricsReader(reference: reference))
    }
}
#endif
