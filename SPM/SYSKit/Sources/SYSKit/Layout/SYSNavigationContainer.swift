#if os(iOS)
import SwiftUI

public struct SYSToolbarAction {
    public let title: String
    public let systemImage: String
    public let action: () -> Void
    let zoomSourceID: String?

    public init(
        _ title: String,
        systemImage: String,
        zoomSourceID: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.zoomSourceID = zoomSourceID
        self.action = action
    }

    public static func close(_ title: String = "Close", action: @escaping () -> Void) -> SYSToolbarAction {
        SYSToolbarAction(title, systemImage: SYSSymbol.close, action: action)
    }

    /// The gear button; pass zoomSourceID to make the screen it opens zoom out of a SYSScreenHeader button.
    public static func settings(
        _ title: String = "Settings",
        zoomSourceID: String? = nil,
        action: @escaping () -> Void
    ) -> SYSToolbarAction {
        SYSToolbarAction(title, systemImage: SYSSymbol.settings, zoomSourceID: zoomSourceID, action: action)
    }
}

public struct SYSToolbarButton: View {
    private let item: SYSToolbarAction

    public init(_ item: SYSToolbarAction) {
        self.item = item
    }

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.item = SYSToolbarAction(title, systemImage: systemImage, action: action)
    }

    public var body: some View {
        Button {
            SYSHaptics.light()
            item.action()
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .labelStyle(.iconOnly)
        }
    }
}

/// A navigation stack that draws the page theme's backdrop behind its content and tints with the theme accent unless told otherwise.
public struct SYSNavigationContainer<Content: View, Accessory: View>: View {
    @Environment(\.sysPageTheme) private var theme
    private let tint: Color?
    private let title: String?
    private let accessory: Accessory
    private let trailing: SYSToolbarAction?
    private let content: Content

    public init(
        tint: Color? = nil,
        title: String? = nil,
        accessory: Accessory,
        trailing: SYSToolbarAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.title = title
        self.accessory = accessory
        self.trailing = trailing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { screen }
                .tint(tint ?? theme.accent)
        } else {
            NavigationView { screen }
                .navigationViewStyle(.stack)
                .tint(tint ?? theme.accent)
        }
    }

    private var screen: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sysPageBackground()
            .sysNavigationBar(title: title, accessory: accessory, trailing: trailing)
    }
}

public extension SYSNavigationContainer where Accessory == EmptyView {
    init(
        tint: Color? = nil,
        title: String? = nil,
        trailing: SYSToolbarAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(tint: tint, title: title, accessory: EmptyView(), trailing: trailing, content: content)
    }
}

public extension View {
    func sysNavigationBar<Accessory: View>(
        title: String? = nil,
        accessory: Accessory,
        trailing: SYSToolbarAction? = nil
    ) -> some View {
        modifier(SYSNavigationBar(title: title, accessory: accessory, trailing: trailing))
    }

    func sysNavigationBar(title: String? = nil, trailing: SYSToolbarAction? = nil) -> some View {
        sysNavigationBar(title: title, accessory: EmptyView(), trailing: trailing)
    }
}

private struct SYSNavigationBar<Accessory: View>: ViewModifier {
    let title: String?
    let accessory: Accessory
    let trailing: SYSToolbarAction?

    func body(content: Content) -> some View {
        withAccessory(withTrailing(titled(content)))
    }

    @ViewBuilder
    private func withAccessory(_ content: some View) -> some View {
        if Accessory.self != EmptyView.self {
            content.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { accessory }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func withTrailing(_ content: some View) -> some View {
        if let trailing {
            content.toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { SYSToolbarButton(trailing) }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func titled(_ content: Content) -> some View {
        if let title {
            content.sysNavigationTitle(title)
        } else {
            content.navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A large title with an optional glass button at the trailing edge, drawn in the content so the button can be the
/// source of a zoom transition (a system bar button cannot be). Hide the navigation bar with sysHidesNavigationBar().
public struct SYSScreenHeader: View {
    @Environment(\.sysZoomNamespace) private var zoomNamespace
    private let title: String
    private let trailing: SYSToolbarAction?

    public init(_ title: String, trailing: SYSToolbarAction? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: SYSSpace.md) {
            Text(title)
                .font(SYSFont.rounded.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if let trailing {
                Button {
                    SYSHaptics.light()
                    trailing.action()
                } label: {
                    Label(trailing.title, systemImage: trailing.systemImage)
                        .labelStyle(.iconOnly)
                        .font(SYSFont.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: SYSSize.touch, height: SYSSize.touch)
                        .background(Circle().fill(.thinMaterial))
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: SYSStroke.hairline))
                }
                .buttonStyle(.plain)
                .sysZoomSource(
                    id: trailing.zoomSourceID ?? "",
                    in: trailing.zoomSourceID == nil ? nil : zoomNamespace,
                    cornerRadius: SYSSize.touch / 2
                )
            }
        }
    }
}
#endif
