#if os(iOS)
import SwiftUI

/// The app's web links (support, privacy, terms, website) as one Settings section. The list, the words and the addresses
/// come from the served config, so they change without an app update. Pass the app's parental gate in a kids app.
public struct SYSLinksSection: View {
    @Environment(\.sysSettingsStyle) private var style
    private let title: String?
    private let languages: [String]
    private let gate: SYSParentalGate?

    public init(title: String? = nil, languages: [String] = Locale.preferredLanguages, gate: SYSParentalGate? = nil) {
        self.title = title
        self.languages = languages
        self.gate = gate
    }

    public var body: some View {
        let links = SYSConfig.shared.links(for: languages)
        if !links.isEmpty {
            SYSSettingsSection(title ?? SYSConfig.shared.linksTitle(for: languages)) {
                ForEach(links) { link in
                    SYSSettingsRow(
                        icon: link.symbol,
                        tint: style.linkTint,
                        title: link.title,
                        chevron: SYSSymbol.openLink
                    ) {
                        SYSHaptics.light()
                        SYSLinkOpener.open(link.url, gate: gate)
                    }
                    .accessibilityHint(link.url.host ?? "")
                }
            }
        }
    }
}

@MainActor
enum SYSLinkOpener {
    static func open(_ url: URL, gate: SYSParentalGate?) {
        guard let gate else {
            UIApplication.shared.open(url)
            return
        }
        gate.trigger { UIApplication.shared.open(url) }
    }
}
#endif
