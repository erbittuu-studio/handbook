#if os(iOS)
import UIKit

/// The words on the notice that says why an item cannot be opened. SYSKit carries translations (`forLanguages`).
public struct SYSContentNoticeText: Sendable {
    public var needsInternetTitle: String
    public var needsInternetMessage: String
    public var failedTitle: String
    public var failedMessage: String
    public var ok: String

    public init(
        needsInternetTitle: String = "Needs internet once",
        needsInternetMessage: String = "This has not been downloaded yet. Connect to the internet once and it will be saved for offline use.",
        failedTitle: String = "Could not download",
        failedMessage: String = "Something went wrong while downloading this. Please try again.",
        ok: String = "OK"
    ) {
        self.needsInternetTitle = needsInternetTitle
        self.needsInternetMessage = needsInternetMessage
        self.failedTitle = failedTitle
        self.failedMessage = failedMessage
        self.ok = ok
    }

    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSContentNoticeText {
        SYSLocale.match(translations, for: languages) ?? SYSContentNoticeText()
    }

    static let translations: [String: SYSContentNoticeText] = [
        "en": SYSContentNoticeText(),
        "hi": SYSContentNoticeText(
            needsInternetTitle: "एक बार इंटरनेट चाहिए",
            needsInternetMessage: "यह अभी डाउनलोड नहीं हुआ है। एक बार इंटरनेट से जुड़ें, फिर यह ऑफ़लाइन उपयोग के लिए सहेज लिया जाएगा।",
            failedTitle: "डाउनलोड नहीं हो सका",
            failedMessage: "इसे डाउनलोड करते समय कुछ गड़बड़ हो गई। कृपया फिर से प्रयास करें।",
            ok: "ठीक है"
        ),
        "gu": SYSContentNoticeText(
            needsInternetTitle: "એક વાર ઇન્ટરનેટ જોઈએ",
            needsInternetMessage: "આ હજી ડાઉનલોડ થયું નથી. એક વાર ઇન્ટરનેટ સાથે જોડાઓ, પછી તે ઓફલાઇન ઉપયોગ માટે સચવાઈ જશે.",
            failedTitle: "ડાઉનલોડ થઈ શક્યું નહીં",
            failedMessage: "આને ડાઉનલોડ કરતી વખતે કંઈક ખોટું થયું. કૃપા કરીને ફરી પ્રયાસ કરો.",
            ok: "બરાબર"
        )
    ]
}

enum SYSContentNotice {
    @MainActor
    static func show(_ access: SYSItemAccess, languages: [String]) {
        guard access != .ready, let presenter = SYSUpdateReminder.topViewController() else { return }
        let text = SYSContentNoticeText.forLanguages(languages)
        let needsInternet = access == .needsInternet
        let alert = UIAlertController(
            title: needsInternet ? text.needsInternetTitle : text.failedTitle,
            message: needsInternet ? text.needsInternetMessage : text.failedMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: text.ok, style: .cancel))
        presenter.present(alert, animated: true)
    }
}
#endif
