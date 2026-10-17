import Foundation

/// The words on the app suggestion sheet. SYSKit carries translations (`forLanguages`); an app may pass its own text.
public struct SYSAppSuggestionText: Sendable {
    public var title: String
    public var download: String
    public var another: String
    public var later: String
    public var close: String
    public var languages: [String]

    public init(
        title: String = "You may also like",
        download: String = "Download",
        another: String = "Another app",
        later: String = "Remind me later",
        close: String = "Close",
        languages: [String] = Locale.preferredLanguages
    ) {
        self.title = title
        self.download = download
        self.another = another
        self.later = later
        self.close = close
        self.languages = languages
    }

    /// The text in the first of the given languages that has a translation, English otherwise.
    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSAppSuggestionText {
        var text = SYSLocale.match(translations, for: languages) ?? SYSAppSuggestionText()
        text.languages = languages
        return text
    }

    static let translations: [String: SYSAppSuggestionText] = [
        "en": SYSAppSuggestionText(),
        "hi": SYSAppSuggestionText(
            title: "आपको ये भी पसंद आ सकता है",
            download: "डाउनलोड करें",
            another: "दूसरा ऐप",
            later: "बाद में याद दिलाएं",
            close: "बंद करें"
        ),
        "gu": SYSAppSuggestionText(
            title: "તમને આ પણ ગમશે",
            download: "ડાઉનલોડ કરો",
            another: "બીજી એપ",
            later: "પછી યાદ અપાવો",
            close: "બંધ કરો"
        )
    ]
}
