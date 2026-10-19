#if os(iOS)
import SwiftUI
import UIKit

/// The colors the app suggestion sheet is drawn in, so each app keeps its own look.
public struct SYSAppSuggestionStyle {
    public var accent: Color
    public var onAccent: Color

    public init(accent: Color, onAccent: Color = .white) {
        self.accent = accent
        self.onAccent = onAccent
    }
}

/// Now and then, on the dashboard, suggests one of the portfolio's other apps in a sheet: Download opens its store page,
/// Another app shows the next one, Remind me later brings the sheet back in a couple of days.
@MainActor
enum SYSAppSuggestion {
    static let lastShownKey = SYSSettingsKey<Date?>("sys.appSuggestion.lastShown", default: nil)
    static let remindAfterKey = SYSSettingsKey<Date?>("sys.appSuggestion.remindAfter", default: nil)
    static let seenKey = SYSSettingsKey<[String]>("sys.appSuggestion.seen", default: [])
    static let openedKey = SYSSettingsKey<[String]>("sys.appSuggestion.opened", default: [])
    static let opensKey = SYSSettingsKey<Int>("sys.appSuggestion.opens", default: 0)
    static let shownCountKey = SYSSettingsKey<Int>("sys.appSuggestion.shownCount", default: 0)
    static let nextOpenKey = SYSSettingsKey<Int>("sys.appSuggestion.nextOpen", default: SYSAppSuggestionPolicy.firstOpen)

    /// Counts one open of the app: a launch, or coming back to the dashboard after being away for a while.
    static func recordOpen(settings: SYSSettings = .shared) {
        settings[opensKey] += 1
    }

    @discardableResult
    static func showIfDue(style: SYSAppSuggestionStyle, text: SYSAppSuggestionText, settings: SYSSettings = .shared) -> Bool {
        SYSAppCatalog.shared.load()
        let apps = SYSAppCatalog.shared.otherApps
        guard !apps.isEmpty,
              SYSConnectivity.shared.isOnline,
              !SYSPromptTraffic.popupShowing,
              !SYSAppSuggestionPolicy.reviewMayBeOpen(lastRequest: SYSPromptTraffic.lastReviewRequest, now: Date()),
              UIApplication.shared.applicationState == .active
        else { return false }

        let now = Date()
        let ownApp = SYSAppCatalog.shared.thisApp
        guard SYSAppSuggestionPolicy.isDue(
                opens: settings[opensKey],
                nextOpen: settings[nextOpenKey],
                lastShown: settings[lastShownKey],
                remindAfter: settings[remindAfterKey],
                now: now
              ),
              let next = SYSAppSuggestionPolicy.next(
                from: apps,
                seen: settings[seenKey],
                opened: settings[openedKey],
                recommends: ownApp?.recommends ?? [],
                category: ownApp?.category
              ),
              let presenter = SYSUpdateReminder.topViewController()
        else { return false }

        settings[lastShownKey] = now
        settings[remindAfterKey] = nil
        settings[shownCountKey] += 1
        settings[nextOpenKey] = SYSAppSuggestionPolicy.nextOpen(after: settings[opensKey], shownCount: settings[shownCountKey])
        settings[seenKey] = next.seen

        let model = SYSAppSuggestionModel(app: next.app, apps: apps, settings: settings)
        let dismisser = SYSPopupDismisser()
        let host = UIHostingController(
            rootView: SYSAppSuggestionView(model: model, style: style, text: text, close: { dismisser.dismiss() })
                .sysMetrics()
        )
        dismisser.host = host
        host.view.backgroundColor = .clear
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        SYSPromptTraffic.popupShowing = true
        presenter.present(host, animated: true)
        SYSLogger.info("suggestion: showing \(next.app.id)")
        return true
    }
}

@MainActor
final class SYSAppSuggestionModel: ObservableObject {
    @Published private(set) var app: SYSAppCatalogEntry
    @Published private(set) var hasAnother: Bool

    private let apps: [SYSAppCatalogEntry]
    private let settings: SYSSettings

    init(app: SYSAppCatalogEntry, apps: [SYSAppCatalogEntry], settings: SYSSettings) {
        self.app = app
        self.apps = apps
        self.settings = settings
        hasAnother = SYSAppSuggestionPolicy.hasAnother(apps: apps, opened: settings[SYSAppSuggestion.openedKey])
    }

    func download() {
        settings[SYSAppSuggestion.openedKey] += [app.id]
        guard let string = app.appStoreUrl, let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    func showAnother() {
        let others = apps.filter { $0.id != app.id }
        let ownApp = SYSAppCatalog.shared.thisApp
        guard let next = SYSAppSuggestionPolicy.next(
            from: others,
            seen: settings[SYSAppSuggestion.seenKey],
            opened: settings[SYSAppSuggestion.openedKey],
            recommends: ownApp?.recommends ?? [],
            category: ownApp?.category
        ) else { return }
        settings[SYSAppSuggestion.seenKey] = Array(Set(next.seen + [app.id]))
        app = next.app
    }

    func remindLater() {
        settings[SYSAppSuggestion.remindAfterKey] = Date().addingTimeInterval(SYSAppSuggestionPolicy.remindDelay)
    }
}

struct SYSAppSuggestionView: View {
    @ObservedObject var model: SYSAppSuggestionModel
    let style: SYSAppSuggestionStyle
    let text: SYSAppSuggestionText
    let close: () -> Void

    @Environment(\.sysMetrics) private var metrics
    @State private var shown = false

    private var sideBySide: Bool { metrics.isCompactHeight }
    private var roomy: Bool { !metrics.isCompactWidth && !sideBySide }

    private var icon: CGFloat {
        let fraction = sideBySide ? 0.24 : 0.22
        return min(max(metrics.shortSide * fraction, sideBySide ? 56 : 72), sideBySide ? 88 : (roomy ? 144 : 112))
    }

    private var cardWidth: CGFloat {
        let available = metrics.contentSize.width - metrics.screenMargin * 2
        let readable: CGFloat = sideBySide ? 640 : (metrics.isCompactWidth ? 360 : 540)
        return max(min(available, readable), 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.45 : 0)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                card
                    .padding(.vertical, SYSSpace.xl)
                    .frame(maxWidth: .infinity, minHeight: metrics.contentSize.height)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
            }
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { shown = true }
        }
    }

    private var card: some View {
        Group {
            if sideBySide { wide } else { tall }
        }
        .id(model.app.id)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .padding(.horizontal, SYSSpace.xl)
        .padding(.top, sideBySide ? SYSSpace.xxl + SYSSpace.sm : SYSSpace.xl + SYSSpace.sm)
        .padding(.bottom, SYSSpace.md)
        .frame(width: cardWidth)
        .background(
            ZStack(alignment: .top) {
                Color(.systemBackground)
                LinearGradient(colors: [style.accent.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) { closeButton }
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {}
        .animation(SYSMotion.standard, value: model.app.id)
    }

    private var tall: some View {
        VStack(spacing: SYSSpace.lg) {
            VStack(spacing: SYSSpace.sm + 2) {
                tag
                iconView.padding(.top, SYSSpace.xs)
                nameView
                details
            }
            buttons
        }
    }

    private var wide: some View {
        HStack(alignment: .center, spacing: SYSSpace.xl) {
            VStack(spacing: SYSSpace.sm) {
                iconView
                nameView
            }
            .frame(width: max(icon + SYSSpace.xl, cardWidth * 0.3))

            VStack(spacing: SYSSpace.sm + 2) {
                tag
                details
                buttons
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, SYSSpace.sm)
    }

    private var tag: some View {
        Text(text.title.uppercased())
            .font((roomy ? SYSFont.caption : SYSFont.caption2).weight(.bold))
            .tracking(1.2)
            .foregroundColor(style.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var iconView: some View {
        SYSRemoteImage(url: model.app.iconURL, maxPixelSize: icon * 3) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(SYSOpacity.light)
        }
        .frame(width: icon, height: icon)
        .clipShape(RoundedRectangle(cornerRadius: icon * 0.2237, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .accessibilityHidden(true)
    }

    private var nameView: some View {
        Text(model.app.shortName)
            .font((roomy ? SYSFont.rounded.title : SYSFont.rounded.title2).weight(.bold))
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        let blurb = model.app.blurb(for: text.languages)
        let meta = model.app.highlights(for: text.languages).prefix(3).joined(separator: "  ·  ")

        return VStack(spacing: SYSSpace.sm) {
            if let blurb {
                Text(blurb)
                    .font(roomy ? SYSFont.body : SYSFont.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !meta.isEmpty {
                Text(meta)
                    .font((roomy ? SYSFont.subheadline : SYSFont.footnote).weight(.semibold))
                    .foregroundColor(style.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Image(systemName: SYSSymbol.close)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.secondary.opacity(SYSOpacity.light)))
                .frame(width: SYSSize.touch, height: SYSSize.touch)
        }
        .buttonStyle(.plain)
        .padding(SYSSpace.xs)
        .accessibilityLabel(text.close)
    }

    private var buttons: some View {
        VStack(spacing: SYSSpace.xs) {
            Button {
                SYSHaptics.light()
                model.download()
                close()
            } label: {
                Text(text.download)
                    .font((roomy ? SYSFont.title3 : SYSFont.body).weight(.bold))
                    .foregroundColor(style.onAccent)
                    .frame(maxWidth: .infinity, minHeight: SYSSize.touch + (roomy ? 14 : 6))
                    .background(Capsule().fill(style.accent))
            }
            .buttonStyle(SYSPressStyle())

            HStack(spacing: 0) {
                textButton(text.later) {
                    model.remindLater()
                    close()
                }
                if model.hasAnother {
                    Rectangle()
                        .fill(Color.secondary.opacity(SYSOpacity.medium))
                        .frame(width: SYSStroke.thin, height: 18)
                        .accessibilityHidden(true)
                    textButton(text.another, tint: style.accent) {
                        SYSHaptics.light()
                        model.showAnother()
                    }
                }
            }
        }
    }

    private func textButton(_ title: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font((roomy ? SYSFont.body : SYSFont.subheadline).weight(.semibold))
                .foregroundColor(tint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: SYSSize.touch)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class SYSPopupDismisser {
    weak var host: UIViewController?

    func dismiss() {
        SYSPromptTraffic.popupShowing = false
        host?.dismiss(animated: true)
    }
}
#endif
