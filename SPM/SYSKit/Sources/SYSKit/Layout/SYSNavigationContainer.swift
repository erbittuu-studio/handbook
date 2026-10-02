#if os(iOS)
import SwiftUI

public struct SYSToolbarAction {
    public let title: String
    public let systemImage: String
    public let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public static func close(_ title: String = "Close", action: @escaping () -> Void) -> SYSToolbarAction {
        SYSToolbarAction(title, systemImage: SYSSymbol.close, action: action)
    }

    public static func settings(_ title: String = "Settings", action: @escaping () -> Void) -> SYSToolbarAction {
        SYSToolbarAction(title, systemImage: SYSSymbol.settings, action: action)
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

public struct SYSNavigationContainer<Content: View, Background: View, Accessory: View>: View {
    private let tint: Color
    private let title: String?
    private let background: Background?
    private let accessory: Accessory
    private let trailing: SYSToolbarAction?
    private let content: Content

    public init(
        tint: Color,
        title: String? = nil,
        background: Background,
        accessory: Accessory,
        trailing: SYSToolbarAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.title = title
        self.background = background
        self.accessory = accessory
        self.trailing = trailing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { screen }
                .tint(tint)
        } else {
            NavigationView { screen }
                .navigationViewStyle(.stack)
                .tint(tint)
        }
    }

    private var screen: some View {
        content
            .modifier(SYSBackdrop(background: background))
            .sysNavigationBar(title: title, accessory: accessory, trailing: trailing)
    }
}

public extension SYSNavigationContainer where Background == EmptyView, Accessory == EmptyView {
    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.title = nil
        self.background = nil
        self.accessory = EmptyView()
        self.trailing = nil
        self.content = content()
    }
}

public extension SYSNavigationContainer where Accessory == EmptyView {
    init(
        tint: Color,
        title: String? = nil,
        background: Background,
        trailing: SYSToolbarAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tint: tint,
            title: title,
            background: background,
            accessory: EmptyView(),
            trailing: trailing,
            content: content
        )
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

private struct SYSBackdrop<Background: View>: ViewModifier {
    let background: Background?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let background {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
        } else {
            content
        }
    }
}
#endif
