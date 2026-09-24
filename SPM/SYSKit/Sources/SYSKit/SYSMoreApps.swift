#if canImport(SwiftUI)
import SwiftUI

/// A ready-made "More apps" section: the rest of the studio's portfolio, from
/// `SYSAppCatalog`, with no fetching code of its own — `SYSBootstrap.start`
/// already refreshes the catalog in the background.
///
///     List {
///         …
///         SYSMoreAppsSection()
///     }
///
/// Renders nothing until there is something to show — nothing cached yet, or
/// a portfolio of one — so it never leaves an empty header behind.
public struct SYSMoreAppsSection: View {
    private let title: String
    private let catalog: SYSAppCatalog

    public init(title: String = "More from us", catalog: SYSAppCatalog = .shared) {
        self.title = title
        self.catalog = catalog
    }

    public var body: some View {
        let apps = catalog.otherApps
        if !apps.isEmpty {
            Section(title) {
                ForEach(apps, id: \.id) { app in
                    SYSMoreAppRow(app: app)
                }
            }
        }
    }
}

private struct SYSMoreAppRow: View {
    let app: SYSAppCatalogEntry

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .foregroundColor(.primary)
                    if let tagline = app.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.app")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            if let iconURL {
                AsyncImage(url: iconURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.clear }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: 44, height: 44)
    }

    private var iconURL: URL? {
        guard let path = app.iconPath else { return nil }
        return URL(string: "\(SYSHosting.baseURL)/\(app.id)/\(path)")
    }

    private func open() {
        #if canImport(UIKit) && !os(watchOS)
        guard let urlString = app.appStoreUrl, let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
#endif
