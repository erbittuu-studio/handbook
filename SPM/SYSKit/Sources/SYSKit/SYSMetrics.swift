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
    public var regions: [SYSRegion]
    public var reference: Reference

    public init(
        size: CGSize,
        safeArea: SYSInsets = .zero,
        horizontalClass: SYSSizeClass = .compact,
        verticalClass: SYSSizeClass = .regular,
        regions: [SYSRegion] = [],
        reference: Reference = .phone
    ) {
        self.size = size
        self.safeArea = safeArea
        self.horizontalClass = horizontalClass
        self.verticalClass = verticalClass
        self.regions = regions
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

    public var isCompactWidth: Bool { horizontalClass == .compact }
    public var isCompactHeight: Bool { verticalClass == .compact }
    public var prefersSideBySide: Bool { !isCompactWidth || isCompactHeight }

    public func columns(
        minimumWidth: CGFloat,
        spacing: CGFloat = 0,
        minimumColumns: Int = 1,
        even: Bool? = nil,
        in width: CGFloat? = nil
    ) -> Int {
        let pitch = minimumWidth + spacing
        let available = width ?? contentSize.width
        let fit = pitch > 0 ? Int((available + spacing) / pitch) : 1
        let count = (even ?? hasFold) ? fit - fit % 2 : fit
        return max(minimumColumns, count)
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
                        regions: sysRegions(in: proxy),
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
