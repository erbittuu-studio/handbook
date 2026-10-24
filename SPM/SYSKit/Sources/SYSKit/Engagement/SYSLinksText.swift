import Foundation

/// The words around the app's web links and the other-apps cards. SYSKit carries translations (`forLanguages`) in the
/// portfolio's languages, so the config holds only the website address; a config entry or a catalog label can still override one.
public struct SYSLinksText: Sendable, Equatable {
    public var about: String
    public var support: String
    public var privacy: String
    public var terms: String
    public var website: String
    public var get: String
    public var open: String

    public init(
        about: String = "About",
        support: String = "Support",
        privacy: String = "Privacy Policy",
        terms: String = "Terms of Use",
        website: String = "Website",
        get: String = "Get",
        open: String = "Open"
    ) {
        self.about = about
        self.support = support
        self.privacy = privacy
        self.terms = terms
        self.website = website
        self.get = get
        self.open = open
    }

    /// The text in the first of the given languages that has a translation, English otherwise.
    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSLinksText {
        SYSLocale.match(translations, for: languages) ?? SYSLinksText()
    }

    func title(forLink id: String) -> String? {
        switch id {
        case "support": return support
        case "privacy": return privacy
        case "terms": return terms
        case "website": return website
        default: return nil
        }
    }

    static let translations: [String: SYSLinksText] = [
        "en": SYSLinksText(),
        "hi": SYSLinksText(about: "जानकारी", support: "सहायता", privacy: "गोपनीयता नीति", terms: "उपयोग की शर्तें", website: "वेबसाइट", get: "पाएँ", open: "खोलें"),
        "gu": SYSLinksText(about: "માહિતી", support: "સહાય", privacy: "ગોપનીયતા નીતિ", terms: "ઉપયોગની શરતો", website: "વેબસાઇટ", get: "મેળવો", open: "ખોલો"),
        "de": SYSLinksText(about: "Info", support: "Support", privacy: "Datenschutzerklärung", terms: "Nutzungsbedingungen", website: "Website", get: "Laden", open: "Öffnen"),
        "es": SYSLinksText(about: "Acerca de", support: "Soporte", privacy: "Política de privacidad", terms: "Términos de uso", website: "Sitio web", get: "Obtener", open: "Abrir"),
        "fr": SYSLinksText(about: "À propos", support: "Assistance", privacy: "Politique de confidentialité", terms: "Conditions d’utilisation", website: "Site web", get: "Obtenir", open: "Ouvrir"),
        "it": SYSLinksText(about: "Informazioni", support: "Assistenza", privacy: "Informativa sulla privacy", terms: "Termini di utilizzo", website: "Sito web", get: "Ottieni", open: "Apri"),
        "pt-BR": SYSLinksText(about: "Sobre", support: "Suporte", privacy: "Política de Privacidade", terms: "Termos de Uso", website: "Site", get: "Obter", open: "Abrir"),
        "nl": SYSLinksText(about: "Over", support: "Ondersteuning", privacy: "Privacybeleid", terms: "Gebruiksvoorwaarden", website: "Website", get: "Laad", open: "Open"),
        "pl": SYSLinksText(about: "O aplikacji", support: "Pomoc", privacy: "Polityka prywatności", terms: "Warunki użytkowania", website: "Strona internetowa", get: "Pobierz", open: "Otwórz"),
        "ru": SYSLinksText(about: "О приложении", support: "Поддержка", privacy: "Политика конфиденциальности", terms: "Условия использования", website: "Сайт", get: "Загрузить", open: "Открыть"),
        "tr": SYSLinksText(about: "Hakkında", support: "Destek", privacy: "Gizlilik Politikası", terms: "Kullanım Koşulları", website: "Web Sitesi", get: "Al", open: "Aç"),
        "id": SYSLinksText(about: "Tentang", support: "Dukungan", privacy: "Kebijakan Privasi", terms: "Ketentuan Penggunaan", website: "Situs Web", get: "Dapatkan", open: "Buka"),
        "vi": SYSLinksText(about: "Giới thiệu", support: "Hỗ trợ", privacy: "Chính sách quyền riêng tư", terms: "Điều khoản sử dụng", website: "Trang web", get: "Tải", open: "Mở"),
        "th": SYSLinksText(about: "เกี่ยวกับ", support: "การสนับสนุน", privacy: "นโยบายความเป็นส่วนตัว", terms: "เงื่อนไขการใช้งาน", website: "เว็บไซต์", get: "รับ", open: "เปิด"),
        "ja": SYSLinksText(about: "情報", support: "サポート", privacy: "プライバシーポリシー", terms: "利用規約", website: "ウェブサイト", get: "入手", open: "開く"),
        "ko": SYSLinksText(about: "정보", support: "지원", privacy: "개인정보 처리방침", terms: "이용약관", website: "웹사이트", get: "받기", open: "열기"),
        "zh-Hans": SYSLinksText(about: "关于", support: "支持", privacy: "隐私政策", terms: "使用条款", website: "网站", get: "获取", open: "打开"),
        "zh-Hant": SYSLinksText(about: "關於", support: "支援", privacy: "隱私權政策", terms: "使用條款", website: "網站", get: "取得", open: "開啟"),
        "ar": SYSLinksText(about: "حول", support: "الدعم", privacy: "سياسة الخصوصية", terms: "شروط الاستخدام", website: "الموقع الإلكتروني", get: "احصل", open: "فتح")
    ]
}
