#if os(iOS)
import SwiftUI

public struct SYSMoreAppsSection: View {
    @Environment(\.sysSettingsStyle) private var style
    private let title: String
    private let catalog = SYSAppCatalog.shared

    public init(title: String = "More from us") {
        self.title = title
    }

    public var body: some View {
        let apps = catalog.otherApps
        if !apps.isEmpty {
            SYSSettingsSection(title) {
                ForEach(apps, id: \.id) { app in
                    SYSSettingsRow(
                        icon: nil,
                        iconURL: app.iconURL,
                        tint: style.stroke,
                        title: app.name,
                        subtitle: app.tagline.flatMap { $0.isEmpty ? nil : $0 },
                        chevron: SYSSymbol.openApp
                    ) {
                        SYSHaptics.light()
                        guard let string = app.appStoreUrl, let url = URL(string: string) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}
#endif
