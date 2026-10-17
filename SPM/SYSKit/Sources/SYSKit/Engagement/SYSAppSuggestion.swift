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

    @State private var shown = false
    @ScaledMetric(relativeTo: .body) private var icon: CGFloat = 92

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(shown ? 0.5 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                ScrollView(showsIndicators: false) {
                    card
                        .frame(maxWidth: 420)
                        .padding(.horizontal, SYSSpace.xl)
                        .padding(.vertical, SYSSpace.xl)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scaleEffect(shown ? 1 : 0.88)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { shown = true }
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [style.accent, style.accent.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            content
                .id(model.app.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            buttons
                .padding(.horizontal, SYSSpace.xl)
                .padding(.top, SYSSpace.xl)
                .padding(.bottom, SYSSpace.lg)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 14)
        .animation(SYSMotion.standard, value: model.app.id)
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            gradient
                .frame(height: icon * 0.95)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: icon * 1.5, height: icon * 1.5)
                        .offset(x: icon * 0.5, y: -icon * 0.6)
                }
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: icon * 0.9, height: icon * 0.9)
                        .offset(x: -icon * 0.3, y: icon * 0.1)
                }
                .overlay(alignment: .topLeading) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(SYSSpace.xl)
                        .accessibilityHidden(true)
                }

            AsyncImage(url: model.app.iconURL) { $0.resizable().scaledToFill() } placeholder: {
                Color.secondary.opacity(SYSOpacity.light)
            }
            .frame(width: icon, height: icon)
            .clipShape(RoundedRectangle(cornerRadius: icon * 0.2237, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: icon * 0.2237, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
            .offset(y: icon * 0.5)
            .id(model.app.id)
            .accessibilityHidden(true)
        }
        .padding(.bottom, icon * 0.5)
    }

    private var content: some View {
        let app = model.app
        let blurb = app.blurb(for: text.languages)
        let highlights = Array(app.highlights(for: text.languages).prefix(3))

        return VStack(spacing: SYSSpace.md) {
            Text(text.title.uppercased())
                .font(SYSFont.caption2.weight(.bold))
                .tracking(1)
                .foregroundColor(style.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SYSSpace.md)
                .padding(.vertical, SYSSpace.xs + 1)
                .background(Capsule().fill(style.accent.opacity(SYSOpacity.subtle + 0.05)))
                .padding(.top, SYSSpace.lg)

            Text(app.shortName)
                .font(SYSFont.rounded.title2.weight(.heavy))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            if let blurb {
                Text(blurb)
                    .font(SYSFont.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !highlights.isEmpty {
                HStack(spacing: SYSSpace.sm) {
                    ForEach(highlights, id: \.self) { highlight in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(highlight)
                                .font(SYSFont.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(style.accent)
                        .padding(.horizontal, SYSSpace.sm + 2)
                        .padding(.vertical, SYSSpace.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: SYSRadius.md, style: .continuous)
                                .fill(style.accent.opacity(SYSOpacity.subtle + 0.05))
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SYSSpace.xs)
            }
        }
        .padding(.horizontal, SYSSpace.xl)
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: SYSSpace.sm + 2) {
            Button {
                SYSHaptics.light()
                model.download()
                close()
            } label: {
                HStack(spacing: SYSSpace.sm) {
                    Image(systemName: "arrow.down.app.fill")
                    Text(text.download)
                }
                .font(SYSFont.body.weight(.bold))
                .foregroundColor(style.onAccent)
                .frame(maxWidth: .infinity, minHeight: SYSSize.touch + 8)
                .background(
                    RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous).fill(gradient)
                )
                .shadow(color: style.accent.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(SYSPressStyle())

            if model.hasAnother {
                Button {
                    SYSHaptics.light()
                    model.showAnother()
                } label: {
                    HStack(spacing: SYSSpace.sm) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(text.another)
                    }
                    .font(SYSFont.body.weight(.semibold))
                    .foregroundColor(style.accent)
                    .frame(maxWidth: .infinity, minHeight: SYSSize.touch + 2)
                    .background(
                        RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous)
                            .fill(style.accent.opacity(SYSOpacity.subtle + 0.05))
                    )
                }
                .buttonStyle(SYSPressStyle())
            }

            Button {
                model.remindLater()
                close()
            } label: {
                Text(text.later)
                    .font(SYSFont.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: SYSSize.touch - SYSSpace.sm)
            }
            .buttonStyle(.plain)
        }
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
