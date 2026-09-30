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

public struct SYSRegion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case division
        case occlusion
    }

    public var kind: Kind
    public var frame: CGRect
    public var isActive: Bool

    public init(kind: Kind, frame: CGRect, isActive: Bool) {
        self.kind = kind
        self.frame = frame
        self.isActive = isActive
    }
}

public struct SYSMetrics: Equatable, Sendable {
    public var size: CGSize
    public var safeArea: SYSInsets
    public var horizontalClass: SYSSizeClass
    public var verticalClass: SYSSizeClass
    public var regions: [SYSRegion]

    public init(
        size: CGSize,
        safeArea: SYSInsets = .zero,
        horizontalClass: SYSSizeClass = .compact,
        verticalClass: SYSSizeClass = .regular,
        regions: [SYSRegion] = []
    ) {
        self.size = size
        self.safeArea = safeArea
        self.horizontalClass = horizontalClass
        self.verticalClass = verticalClass
        self.regions = regions
    }

    public static let unmeasured = SYSMetrics(size: CGSize(width: 393, height: 759))

    public var contentSize: CGSize {
        CGSize(
            width: max(size.width - safeArea.horizontal, 1),
            height: max(size.height - safeArea.vertical, 1)
        )
    }

    public var contentFrame: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    public var hasFold: Bool {
        regions.contains { $0.kind == .division }
    }

    public var isFolded: Bool {
        regions.contains { $0.kind == .division && $0.isActive }
    }

    public var occlusions: [CGRect] {
        regions.filter { $0.kind == .occlusion && $0.isActive }.map(\.frame)
    }

    public var usableFrames: [CGRect] {
        regions
            .filter { $0.kind == .division && $0.isActive }
            .reduce([contentFrame]) { frames, region in
                frames.flatMap { SYSMetrics.split($0, around: region.frame) }
            }
    }

    private static func split(_ frame: CGRect, around region: CGRect) -> [CGRect] {
        guard frame.intersects(region) else { return [frame] }
        let pieces: [CGRect]
        if region.height >= region.width {
            pieces = [
                CGRect(x: frame.minX, y: frame.minY, width: region.minX - frame.minX, height: frame.height),
                CGRect(x: region.maxX, y: frame.minY, width: frame.maxX - region.maxX, height: frame.height)
            ]
        } else {
            pieces = [
                CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: region.minY - frame.minY),
                CGRect(x: frame.minX, y: region.maxY, width: frame.width, height: frame.maxY - region.maxY)
            ]
        }
        return pieces.filter { $0.width > 0 && $0.height > 0 }
    }

    public var shortSide: CGFloat { min(contentSize.width, contentSize.height) }

    public var isCompactWidth: Bool { horizontalClass == .compact }
    public var isCompactHeight: Bool { verticalClass == .compact }
    public var prefersSideBySide: Bool { contentSize.width > contentSize.height }
    public var screenMargin: CGFloat { isCompactWidth ? 20 : 32 }
    public var sectionSpacing: CGFloat { isCompactWidth ? 28 : 36 }
    public var cardColumnWidth: CGFloat { isCompactWidth ? 150 : 220 }

    public func margin(readableWidth: CGFloat, minimum: CGFloat = 0, in width: CGFloat? = nil) -> CGFloat {
        let available = width ?? contentSize.width
        return max(minimum, (available - readableWidth) / 2)
    }
}

#if os(iOS)
import SwiftUI

private struct SYSMetricsKey: EnvironmentKey {
    static let defaultValue = SYSMetrics.unmeasured
}

public extension EnvironmentValues {
    var sysMetrics: SYSMetrics {
        get { self[SYSMetricsKey.self] }
        set { self[SYSMetricsKey.self] = newValue }
    }
}

private extension SYSRegion {
    @available(iOS 27.1, *)
    init(_ region: ReservedRegion) {
        self.init(
            kind: region.kind == .division ? .division : .occlusion,
            frame: region.frame,
            isActive: region.isActive
        )
    }
}

private func sysRegions(in proxy: GeometryProxy) -> [SYSRegion] {
    guard #available(iOS 27.1, *) else { return [] }
    return [ReservedRegion.Kind.division, .occlusion].flatMap { kind in
        proxy.reservedRegions(kind: kind, options: .includeInactive).map(SYSRegion.init)
    }
}

private extension SYSSizeClass {
    init(_ sizeClass: UserInterfaceSizeClass?) {
        self = sizeClass == .regular ? .regular : .compact
    }
}

private struct SYSMetricsReader: ViewModifier {
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
                        regions: sysRegions(in: proxy)
                    )
                )
        }
    }
}

public extension View {
    func sysMetrics() -> some View {
        modifier(SYSMetricsReader())
    }
}
#endif
