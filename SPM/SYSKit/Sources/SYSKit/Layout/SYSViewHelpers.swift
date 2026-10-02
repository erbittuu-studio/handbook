#if os(iOS)
import SwiftUI
import UIKit

public extension View {
    @ViewBuilder
    /// Hides the default background of a List or Form so the screen background shows through.
    func sysHideScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            onAppear { UITableView.appearance().backgroundColor = .clear }
        }
    }

    @ViewBuilder
    /// Reserves room for a minimum number of text lines so rows keep one height, up to a maximum.
    func sysReservedLines(_ reserved: Int, upTo maximum: Int) -> some View {
        if #available(iOS 16.0, *) {
            lineLimit(reserved...maximum)
        } else {
            lineLimit(maximum)
        }
    }

    @ViewBuilder
    /// A tab bar on iPhone that becomes a sidebar on iPad, on iOS 18 and later.
    func sysAdaptiveTabStyle() -> some View {
        if #available(iOS 18.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }

    @ViewBuilder
    /// Turns the navigation bar content light for dark artwork behind it, on iOS 16 and later.
    func sysDarkNavigationBar(_ enabled: Bool) -> some View {
        if #available(iOS 16.0, *) {
            toolbarColorScheme(enabled ? .dark : nil, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    /// Hides the tab bar while this screen is shown, on iOS 16 and later.
    func sysHidesTabBar() -> some View {
        if #available(iOS 16.0, *) {
            toolbar(.hidden, for: .tabBar)
        } else {
            self
        }
    }

    @ViewBuilder
    /// Medium and large detents with a drag indicator, on iOS 16 and later.
    func sysSheetStyle() -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

/// A rounded rectangle that rounds only the given corners.
public struct SYSRoundedCorner: Shape {
    private let radius: CGFloat
    private let corners: UIRectCorner

    public init(radius: CGFloat, corners: UIRectCorner) {
        self.radius = radius
        self.corners = corners
    }

    public func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

/// A horizontal scroll view that sizes itself to its content height and respects the safe area.
public struct SYSSafeAreaHorizontalScroll<Content: View>: View {
    private let content: Content
    @State private var height: CGFloat = 0

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                content
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(key: SYSScrollHeightKey.self, value: inner.size.height)
                        }
                    )
            }
            .frame(width: proxy.size.width)
        }
        .frame(height: height)
        .clipped()
        .onPreferenceChange(SYSScrollHeightKey.self) { height = $0 }
    }
}

private struct SYSScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The standard empty screen: a symbol, a title and a subtitle, in colors the app supplies.
public struct SYSEmptyState: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = SYSSize.emptyIcon
    private let icon: String
    private let title: String
    private let subtitle: String
    private let iconColor: Color
    private let titleColor: Color
    private let subtitleColor: Color

    public init(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        titleColor: Color,
        subtitleColor: Color
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
    }

    public var body: some View {
        VStack(spacing: SYSSpace.lg) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundColor(iconColor)
            VStack(spacing: SYSSpace.sm) {
                Text(title)
                    .font(SYSFont.rounded.title.weight(.bold))
                    .foregroundColor(titleColor)
                Text(subtitle)
                    .font(SYSFont.title3)
                    .foregroundColor(subtitleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, SYSSpace.xxxl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SYSSpace.xxxl)
    }
}
#endif
