#if os(iOS)
import SwiftUI

@MainActor
public final class SYSHelp: ObservableObject {
    @Published var isComposingMail = false

    private let shareItems: () -> [Any]
    private let onRate: () -> Void
    private let onShareOpened: () -> Void
    private let onShared: (String) -> Void

    public init(
        shareItems: @escaping () -> [Any],
        onRate: @escaping () -> Void = {},
        onShareOpened: @escaping () -> Void = {},
        onShared: @escaping (String) -> Void = { _ in }
    ) {
        self.shareItems = shareItems
        self.onRate = onRate
        self.onShareOpened = onShareOpened
        self.onShared = onShared
    }

    public func rate() {
        SYSHaptics.light()
        onRate()
        SYSAppStore.openReview()
    }

    public func share() {
        SYSHaptics.light()
        onShareOpened()
        SYSShare.present(shareItems()) { [onShared] activityType in
            if let activityType { onShared(activityType) }
        }
    }

    func contact() {
        SYSHaptics.light()
        isComposingMail = true
    }
}

public extension View {
    func sysHelp(_ help: SYSHelp, subject: String = "\(SYSAbout.appName()) support") -> some View {
        modifier(SYSHelpModifier(help: help, subject: subject))
    }
}

private struct SYSHelpModifier: ViewModifier {
    @ObservedObject var help: SYSHelp
    let subject: String

    func body(content: Content) -> some View {
        content.sysSupportMail(isPresented: $help.isComposingMail, subject: subject)
    }
}

public struct SYSHelpSection: View {
    @Environment(\.sysSettingsStyle) private var style
    private let help: SYSHelp
    private let title: String
    private let rateTitle: String
    private let shareTitle: String
    private let contactTitle: String

    public init(help: SYSHelp, title: String, rateTitle: String, shareTitle: String, contactTitle: String) {
        self.help = help
        self.title = title
        self.rateTitle = rateTitle
        self.shareTitle = shareTitle
        self.contactTitle = contactTitle
    }

    public var body: some View {
        SYSSettingsSection(title) {
            SYSSettingsRow(icon: SYSSymbol.starFilled, tint: style.rateTint, title: rateTitle, action: help.rate)
            SYSSettingsRow(icon: SYSSymbol.people, tint: style.shareTint, title: shareTitle, action: help.share)
            SYSSettingsRow(icon: SYSSymbol.email, tint: style.contactTint, title: contactTitle, action: help.contact)
        }
    }
}
#endif
