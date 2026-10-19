#if os(iOS)
import SwiftUI

/// The words on the offline notice. SYSKit carries translations (`forLanguages`); an app may pass its own text.
public struct SYSOfflineText: Sendable {
    public var title: String
    public var message: String
    public var partial: String

    public init(
        title: String = "You're offline",
        message: String = "Saved content still works.",
        partial: String = "Some content is not downloaded yet. Connect once to finish."
    ) {
        self.title = title
        self.message = message
        self.partial = partial
    }

    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSOfflineText {
        SYSLocale.match(translations, for: languages) ?? SYSOfflineText()
    }

    static let translations: [String: SYSOfflineText] = [
        "en": SYSOfflineText(),
        "hi": SYSOfflineText(
            title: "आप ऑफ़लाइन हैं",
            message: "सहेजी हुई सामग्री अब भी चलती है।",
            partial: "कुछ सामग्री अभी डाउनलोड नहीं हुई है। पूरा करने के लिए एक बार इंटरनेट से जुड़ें।"
        ),
        "gu": SYSOfflineText(
            title: "તમે ઓફલાઇન છો",
            message: "સાચવેલી સામગ્રી હજી પણ ચાલે છે.",
            partial: "કેટલી સામગ્રી હજી ડાઉનલોડ થઈ નથી. પૂરી કરવા એક વાર ઇન્ટરનેટ સાથે જોડાઓ."
        )
    ]
}

private struct SYSOfflineNoticeModifier: ViewModifier {
    let text: SYSOfflineText
    let isActive: Bool
    @ObservedObject private var connectivity = SYSConnectivity.shared
    @ObservedObject private var readiness = SYSContentReadiness.shared
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if shown, isActive {
                    notice
                        .padding(.horizontal, SYSSpace.lg)
                        .padding(.top, SYSSpace.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .task(id: connectivity.isOnline) {
                if connectivity.isOnline {
                    withAnimation(SYSMotion.standard) { shown = false }
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(SYSTiming.relaxed * 4 * 1_000_000_000))
                    if Task.isCancelled { return }
                    withAnimation(SYSMotion.standard) { shown = true }
                }
            }
    }

    private var notice: some View {
        HStack(spacing: SYSSpace.sm) {
            Image(systemName: SYSSymbol.offline)
                .font(SYSFont.footnote.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text(text.title).font(SYSFont.footnote.weight(.semibold))
                Text(readiness.missing > 0 ? text.partial : text.message).font(SYSFont.caption).foregroundColor(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, SYSSpace.md)
        .padding(.vertical, SYSSpace.sm)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(SYSOpacity.subtle), lineWidth: SYSStroke.thin)
        )
        .accessibilityElement(children: .combine)
    }
}

public extension View {
    /// Shows a small notice at the top while the device has no connection, a moment after it is lost, and hides it
    /// when the connection returns. Attach it to the screen the person lands on.
    /// - `isActive`: pass false while the screen is covered, so the notice waits for it to be on screen again.
    func sysOfflineNotice(_ text: SYSOfflineText = .forLanguages(), isActive: Bool = true) -> some View {
        modifier(SYSOfflineNoticeModifier(text: text, isActive: isActive))
    }
}
#endif
