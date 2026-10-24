#if os(iOS)
import SwiftUI

/// The portfolio's other apps as cards in Settings: icon, name, one line about the app and a Get or Open button.
/// The list, the lines and the button words come from the served app list. Apps already installed move to the end.
/// Pass the app's parental gate in a kids app, since both buttons leave the app.
public struct SYSMoreAppsSection: View {
    @Environment(\.sysSettingsStyle) private var style
    private let title: String
    private let languages: [String]
    private let gate: SYSParentalGate?
    private let catalog = SYSAppCatalog.shared

    public init(title: String = "More from us", languages: [String] = Locale.preferredLanguages, gate: SYSParentalGate? = nil) {
        self.title = title
        self.languages = languages
        self.gate = gate
    }

    public var body: some View {
        let apps = ordered(catalog.otherApps)
        let words = SYSLinksText.forLanguages(languages)
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: SYSSpace.sm) {
                Text(title)
                    .font(SYSFont.callout.weight(.medium))
                    .foregroundColor(style.sectionTitle)
                    .padding(.horizontal, SYSSpace.lg)
                    .accessibilityAddTraits(.isHeader)

                SYSColumnGrid(minimumWidth: 300, spacing: SYSSpace.md) {
                    ForEach(apps, id: \.id) { app in
                        SYSAppCard(
                            app: app,
                            blurb: app.blurb(for: languages),
                            installed: SYSAppSuggestion.isInstalled(app),
                            get: catalog.label("get", for: languages, fallback: words.get),
                            open: catalog.label("open", for: languages, fallback: words.open),
                            gate: gate
                        )
                    }
                }
            }
        }
    }

    private func ordered(_ apps: [SYSAppCatalogEntry]) -> [SYSAppCatalogEntry] {
        apps.filter { !SYSAppSuggestion.isInstalled($0) } + apps.filter(SYSAppSuggestion.isInstalled)
    }
}

private struct SYSAppCard: View {
    @Environment(\.sysSettingsStyle) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconScaled: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 92

    let app: SYSAppCatalogEntry
    let blurb: String?
    let installed: Bool
    let get: String
    let open: String
    let gate: SYSParentalGate?

    private var action: String { installed ? open : get }
    private var icon: CGFloat { min(iconScaled, 72) }

    var body: some View {
        Button(action: go) {
            Group {
                if typeSize.isAccessibilitySize {
                    stacked
                } else {
                    sideBySide
                }
            }
            .padding(SYSSpace.md)
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .leading)
            .background(style.card)
            .clipShape(RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous)
                    .stroke(style.stroke, lineWidth: SYSStroke.thin)
            )
            .contentShape(RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous))
        }
        .buttonStyle(SYSPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([app.shortName, blurb].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(action)
        .accessibilityAddTraits(.isButton)
    }

    private var sideBySide: some View {
        HStack(spacing: SYSSpace.md) {
            iconView
            VStack(alignment: .leading, spacing: SYSSpace.xs) {
                name(lines: 1)
                description(lines: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pill
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: SYSSpace.md) {
            HStack(spacing: SYSSpace.md) {
                iconView
                name(lines: 2)
            }
            description(lines: 5)
            pill
        }
    }

    private var iconView: some View {
        SYSRemoteImage(url: app.iconURL, maxPixelSize: 192) { phase in
            if let image = phase.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(style.stroke.opacity(SYSOpacity.medium))
            }
        }
        .frame(width: icon, height: icon)
        .clipShape(RoundedRectangle(cornerRadius: icon * 0.23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: icon * 0.23, style: .continuous)
                .stroke(style.stroke, lineWidth: SYSStroke.hairline)
        )
    }

    private func name(lines: Int) -> some View {
        Text(app.shortName)
            .font(SYSFont.headline)
            .foregroundColor(style.title)
            .lineLimit(lines)
    }

    @ViewBuilder
    private func description(lines: Int) -> some View {
        if let blurb {
            Text(blurb)
                .font(SYSFont.footnote)
                .foregroundColor(style.subtitle)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pill: some View {
        Text(action)
            .font(SYSFont.subheadline.weight(.semibold))
            .foregroundColor(installed ? style.title : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, SYSSpace.lg)
            .frame(minHeight: SYSSize.touch - SYSSpace.md)
            .background(Capsule().fill(installed ? style.stroke.opacity(SYSOpacity.medium) : Color.accentColor))
    }

    private func go() {
        SYSHaptics.light()
        let target: URL?
        if installed, let scheme = app.urlScheme {
            target = URL(string: "\(scheme)://")
        } else {
            target = app.appStoreUrl.flatMap(URL.init(string:))
        }
        guard let target else { return }
        SYSLinkOpener.open(target, gate: gate)
    }
}
#endif
