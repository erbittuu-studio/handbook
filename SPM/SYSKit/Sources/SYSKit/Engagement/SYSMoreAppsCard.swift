#if os(iOS)
import SwiftUI

/// The colors a more-apps card is drawn in, so each app keeps its own look.
public struct SYSMoreAppsCardStyle {
    public var title: Color
    public var caption: Color
    public var background: Color

    public init(title: Color, caption: Color, background: Color) {
        self.title = title
        self.caption = caption
        self.background = background
    }
}

/// A row of the portfolio's other apps for a home screen: one tap opens an app's store page, behind a parental gate when one is given.
public struct SYSMoreAppsCard: View {
    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 60
    @State private var apps: [SYSAppCatalogEntry]

    private let title: String
    private let openHint: String
    private let style: SYSMoreAppsCardStyle
    private let gate: SYSParentalGate?
    private let catalog = SYSAppCatalog.shared

    public init(
        title: String = "More from us",
        openHint: String = "Opens the App Store",
        style: SYSMoreAppsCardStyle,
        gate: SYSParentalGate? = nil
    ) {
        self.title = title
        self.openHint = openHint
        self.style = style
        self.gate = gate
        SYSAppCatalog.shared.load()
        _apps = State(initialValue: SYSAppCatalog.shared.otherApps)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: SYSSpace.md) {
                    Text(title)
                        .font(SYSFont.rounded.title3.weight(.bold))
                        .foregroundColor(style.title)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: SYSSpace.lg) {
                            ForEach(apps, id: \.id) { app in tile(app) }
                        }
                        .padding(.vertical, SYSSpace.xs)
                    }
                }
                .padding(SYSSpace.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SYSRadius.xl, style: .continuous).fill(style.background)
                )
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .sysAppCatalogDidUpdate)) { _ in refresh() }
    }

    private func refresh() {
        catalog.load()
        apps = catalog.otherApps
    }

    private func tile(_ app: SYSAppCatalogEntry) -> some View {
        Button {
            SYSHaptics.light()
            open(app)
        } label: {
            VStack(spacing: SYSSpace.sm) {
                AsyncImage(url: app.iconURL) { $0.resizable().scaledToFill() } placeholder: { style.caption.opacity(0.15) }
                    .frame(width: icon, height: icon)
                    .clipShape(RoundedRectangle(cornerRadius: icon * 0.2237, style: .continuous))
                Text(Self.shortName(app.name))
                    .font(SYSFont.caption.weight(.medium))
                    .foregroundColor(style.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: max(icon + SYSSpace.md, 76))
            }
            .frame(minWidth: SYSSize.touch, minHeight: SYSSize.touch)
        }
        .buttonStyle(SYSPressStyle())
        .accessibilityLabel(app.name)
        .accessibilityHint(openHint)
    }

    static func shortName(_ name: String) -> String {
        name.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
    }

    private func open(_ app: SYSAppCatalogEntry) {
        guard let string = app.appStoreUrl, let url = URL(string: string) else { return }
        guard let gate else {
            UIApplication.shared.open(url)
            return
        }
        gate.trigger { UIApplication.shared.open(url) }
    }
}
#endif
