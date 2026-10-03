import CoreGraphics

enum SYSSizeClass: Equatable, Sendable {
    case compact
    case regular
}

struct SYSInsets: Equatable, Sendable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat

    static let zero = SYSInsets()

    init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }
}

struct SYSRegion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case division
        case occlusion
    }

    var kind: Kind
    var frame: CGRect
    var isActive: Bool

    init(kind: Kind, frame: CGRect, isActive: Bool) {
        self.kind = kind
        self.frame = frame
        self.isActive = isActive
    }
}

public struct SYSMetrics: Equatable, Sendable {
    public var size: CGSize
    var safeArea: SYSInsets
    var horizontalClass: SYSSizeClass
    var verticalClass: SYSSizeClass
    var regions: [SYSRegion]
    var canvas: SYSDesignCanvas?

    init(
        size: CGSize,
        safeArea: SYSInsets = .zero,
        horizontalClass: SYSSizeClass = .compact,
        verticalClass: SYSSizeClass = .regular,
        regions: [SYSRegion] = [],
        canvas: SYSDesignCanvas? = nil
    ) {
        self.size = size
        self.safeArea = safeArea
        self.horizontalClass = horizontalClass
        self.verticalClass = verticalClass
        self.regions = regions
        self.canvas = canvas
    }

    static let unmeasured = SYSMetrics(size: CGSize(width: 393, height: 759))

    public var contentSize: CGSize {
        CGSize(
            width: max(size.width - safeArea.horizontal, 1),
            height: max(size.height - safeArea.vertical, 1)
        )
    }

    var contentFrame: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    var hasFold: Bool {
        regions.contains { $0.kind == .division }
    }

    var isFolded: Bool {
        regions.contains { $0.kind == .division && $0.isActive }
    }

    var occlusions: [CGRect] {
        regions.filter { $0.kind == .occlusion && $0.isActive }.map(\.frame)
    }

    var usableFrames: [CGRect] {
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

/// The screen a proportional design was drawn on, so sizes written for it can be scaled to any other screen.
public struct SYSDesignCanvas: Equatable, Sendable {
    public let contentSize: CGSize
    public let scaleRange: ClosedRange<CGFloat>
    public let fontShare: CGFloat

    /// `horizontalInsets` and `verticalInsets` are the safe-area totals of the design screen; `fontShare` is how much of the scale text follows, so type grows more gently than shapes.
    public init(
        size: CGSize,
        horizontalInsets: CGFloat = 0,
        verticalInsets: CGFloat = 0,
        scaleRange: ClosedRange<CGFloat> = 0.75...1.5,
        fontShare: CGFloat = 0.65
    ) {
        self.contentSize = CGSize(
            width: max(size.width - horizontalInsets, 1),
            height: max(size.height - verticalInsets, 1)
        )
        self.scaleRange = scaleRange
        self.fontShare = fontShare
    }
}

public extension SYSMetrics {
    /// How much larger or smaller this screen's content area is than the app's design canvas, kept inside the canvas's range; 1 when the app set no canvas.
    var scale: CGFloat {
        guard let canvas else { return 1 }
        let raw = min(contentSize.width / canvas.contentSize.width, contentSize.height / canvas.contentSize.height)
        return min(max(raw, canvas.scaleRange.lowerBound), canvas.scaleRange.upperBound)
    }

    /// A length drawn for the design canvas, scaled to this screen and rounded to a whole point.
    func s(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded()
    }

    /// A font size drawn for the design canvas; it follows only part of the scale so text stays readable on small screens.
    func f(_ value: CGFloat) -> CGFloat {
        (value * (1 + (scale - 1) * (canvas?.fontShare ?? 1))).rounded()
    }
}

#if os(iOS)
import SwiftUI

public extension SYSMetrics {
    /// The safe area around the screen as SwiftUI insets.
    var safeAreaInsets: EdgeInsets {
        EdgeInsets(top: safeArea.top, leading: safeArea.leading, bottom: safeArea.bottom, trailing: safeArea.trailing)
    }
}

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
    let canvas: SYSDesignCanvas?
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
                        canvas: canvas
                    )
                )
        }
    }
}

public extension View {
    /// Measures the screen for everything below; pass a design canvas to have `s` and `f` scale sizes drawn for it.
    func sysMetrics(designCanvas: SYSDesignCanvas? = nil) -> some View {
        modifier(SYSMetricsReader(canvas: designCanvas))
    }
}
#endif
