import Foundation

/// The words on the app suggestion sheet. SYSKit carries translations (`forLanguages`); an app may pass its own text.
public struct SYSAppSuggestionText: Sendable {
    public var title: String
    public var download: String
    public var another: String
    public var later: String
    public var languages: [String]

    public init(
        title: String = "Another app you may like",
        download: String = "Download",
        another: String = "Another app",
        later: String = "Remind me later",
        languages: [String] = Locale.preferredLanguages
    ) {
        self.title = title
        self.download = download
        self.another = another
        self.later = later
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
            title: "हमारा एक और ऐप, शायद आपको पसंद आए",
            download: "डाउनलोड करें",
            another: "दूसरा ऐप",
            later: "बाद में याद दिलाएं"
        ),
        "gu": SYSAppSuggestionText(
            title: "અમારી બીજી એપ, કદાચ તમને ગમશે",
            download: "ડાઉનલોડ કરો",
            another: "બીજી એપ",
            later: "પછી યાદ અપાવો"
        )
    ]
}
