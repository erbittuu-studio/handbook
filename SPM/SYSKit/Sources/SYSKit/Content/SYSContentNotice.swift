#if os(iOS)
import UIKit

/// The words on the notice that says why an item cannot be opened. SYSKit carries translations (`forLanguages`).
public struct SYSContentNoticeText: Sendable {
    public var needsInternetTitle: String
    public var needsInternetMessage: String
    public var failedTitle: String
    public var failedMessage: String
    public var loading: String
    public var retry: String
    public var ok: String

    public init(
        needsInternetTitle: String = "Needs internet once",
        needsInternetMessage: String = "This has not been downloaded yet. " +
            "Connect to the internet once and it will be saved for offline use.",
        failedTitle: String = "Could not download",
        failedMessage: String = "Something went wrong while downloading this. Please try again.",
        loading: String = "Getting this ready…",
        retry: String = "Try again",
        ok: String = "OK"
    ) {
        self.needsInternetTitle = needsInternetTitle
        self.needsInternetMessage = needsInternetMessage
        self.failedTitle = failedTitle
        self.failedMessage = failedMessage
        self.loading = loading
        self.retry = retry
        self.ok = ok
    }

    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSContentNoticeText {
        SYSLocale.match(translations, for: languages) ?? SYSContentNoticeText()
    }

    static let translations: [String: SYSContentNoticeText] = [
        "en": SYSContentNoticeText(
            needsInternetTitle: "Needs internet once",
            needsInternetMessage: "This has not been downloaded yet. Connect to the internet " +
                                    "once and it will be saved for offline use.",
            failedTitle: "Could not download",
            failedMessage: "Something went wrong while downloading this. Please try again.",
            loading: "Getting this ready…",
            retry: "Try again",
            ok: "OK"
        ),
        "hi": SYSContentNoticeText(
            needsInternetTitle: "एक बार इंटरनेट चाहिए",
            needsInternetMessage: "यह अभी डाउनलोड नहीं हुआ है। एक बार इंटरनेट से जुड़ें, " +
                                    "फिर यह ऑफ़लाइन उपयोग के लिए सहेज लिया जाएगा।",
            failedTitle: "डाउनलोड नहीं हो सका",
            failedMessage: "इसे डाउनलोड करते समय कुछ गड़बड़ हो गई। कृपया फिर से प्रयास करें।",
            loading: "तैयार किया जा रहा है…",
            retry: "फिर कोशिश करें",
            ok: "ठीक है"
        ),
        "gu": SYSContentNoticeText(
            needsInternetTitle: "એક વાર ઇન્ટરનેટ જોઈએ",
            needsInternetMessage: "આ હજી ડાઉનલોડ થયું નથી. એક વાર ઇન્ટરનેટ સાથે " +
                                    "જોડાઓ, પછી તે ઓફલાઇન ઉપયોગ માટે સચવાઈ જશે.",
            failedTitle: "ડાઉનલોડ થઈ શક્યું નહીં",
            failedMessage: "આને ડાઉનલોડ કરતી વખતે કંઈક ખોટું થયું. કૃપા કરીને ફરી પ્રયાસ કરો.",
            loading: "તૈયાર કરવામાં આવી રહ્યું છે…",
            retry: "ફરી પ્રયાસ કરો",
            ok: "બરાબર"
        ),
        "ar": SYSContentNoticeText(
            needsInternetTitle: "يتطلب الإنترنت مرة واحدة",
            needsInternetMessage: "لم يتم تنزيل هذا بعد. اتصل بالإنترنت مرة واحدة " +
                                    "وسيتم حفظه للاستخدام بدون اتصال.",
            failedTitle: "تعذّر التنزيل",
            failedMessage: "حدث خطأ أثناء التنزيل. يُرجى المحاولة مرة أخرى.",
            loading: "جارٍ التحضير…",
            retry: "إعادة المحاولة",
            ok: "حسنًا"
        ),
        "de": SYSContentNoticeText(
            needsInternetTitle: "Einmal Internet nötig",
            needsInternetMessage: "Das wurde noch nicht geladen. Verbinde dich einmal mit dem Internet, " +
                                    "dann wird es für die Nutzung ohne Verbindung gespeichert.",
            failedTitle: "Download nicht möglich",
            failedMessage: "Beim Laden ist etwas schiefgelaufen. Bitte versuche es noch einmal.",
            loading: "Wird vorbereitet…",
            retry: "Erneut versuchen",
            ok: "OK"
        ),
        "es": SYSContentNoticeText(
            needsInternetTitle: "Necesita internet una vez",
            needsInternetMessage: "Esto aún no se ha descargado. Conéctate a internet una " +
                                    "vez y se guardará para usarlo sin conexión.",
            failedTitle: "No se pudo descargar",
            failedMessage: "Algo salió mal durante la descarga. Inténtalo de nuevo.",
            loading: "Preparando esto…",
            retry: "Reintentar",
            ok: "OK"
        ),
        "fr": SYSContentNoticeText(
            needsInternetTitle: "Internet nécessaire une fois",
            needsInternetMessage: "Ce contenu n'a pas encore été téléchargé. Connecte-toi à internet une " +
                                    "fois et il sera enregistré pour une utilisation hors connexion.",
            failedTitle: "Téléchargement impossible",
            failedMessage: "Un problème est survenu pendant le téléchargement. Réessaie.",
            loading: "Préparation en cours…",
            retry: "Réessayer",
            ok: "OK"
        ),
        "id": SYSContentNoticeText(
            needsInternetTitle: "Perlu internet sekali",
            needsInternetMessage: "Ini belum diunduh. Sambungkan ke internet sekali dan ini " +
                                    "akan disimpan untuk dipakai tanpa koneksi.",
            failedTitle: "Tidak bisa mengunduh",
            failedMessage: "Terjadi masalah saat mengunduh. Coba lagi.",
            loading: "Sedang disiapkan…",
            retry: "Coba lagi",
            ok: "OK"
        ),
        "it": SYSContentNoticeText(
            needsInternetTitle: "Serve internet una volta",
            needsInternetMessage: "Non è ancora stato scaricato. Collegati a internet una " +
                                    "volta e verrà salvato per l'uso offline.",
            failedTitle: "Impossibile scaricare",
            failedMessage: "Qualcosa è andato storto durante il download. Riprova.",
            loading: "Preparazione in corso…",
            retry: "Riprova",
            ok: "OK"
        ),
        "ja": SYSContentNoticeText(
            needsInternetTitle: "一度インターネットが必要です",
            needsInternetMessage: "まだダウンロードされていません。一度インターネットに接続すると、オフラインで使えるように保存されます。",
            failedTitle: "ダウンロードできませんでした",
            failedMessage: "ダウンロード中に問題が発生しました。もう一度お試しください。",
            loading: "準備しています…",
            retry: "もう一度",
            ok: "OK"
        ),
        "ko": SYSContentNoticeText(
            needsInternetTitle: "인터넷 연결이 한 번 필요해요",
            needsInternetMessage: "아직 다운로드되지 않았어요. 인터넷에 한 번 연결하면 오프라인에서 쓸 수 있도록 저장돼요.",
            failedTitle: "다운로드하지 못했어요",
            failedMessage: "다운로드하는 중에 문제가 생겼어요. 다시 시도해 주세요.",
            loading: "준비하는 중…",
            retry: "다시 시도",
            ok: "확인"
        ),
        "nl": SYSContentNoticeText(
            needsInternetTitle: "Eenmalig internet nodig",
            needsInternetMessage: "Dit is nog niet gedownload. Maak één keer verbinding met internet, " +
                                    "dan wordt het bewaard voor gebruik zonder verbinding.",
            failedTitle: "Downloaden mislukt",
            failedMessage: "Er ging iets mis tijdens het downloaden. Probeer het opnieuw.",
            loading: "Wordt voorbereid…",
            retry: "Opnieuw proberen",
            ok: "OK"
        ),
        "pl": SYSContentNoticeText(
            needsInternetTitle: "Wymagany internet jednorazowo",
            needsInternetMessage: "To nie zostało jeszcze pobrane. Połącz się raz z " +
                                    "internetem, a zostanie zapisane do użytku offline.",
            failedTitle: "Nie udało się pobrać",
            failedMessage: "Podczas pobierania coś poszło nie tak. Spróbuj ponownie.",
            loading: "Przygotowywanie…",
            retry: "Spróbuj ponownie",
            ok: "OK"
        ),
        "pt-BR": SYSContentNoticeText(
            needsInternetTitle: "Precisa de internet uma vez",
            needsInternetMessage: "Isso ainda não foi baixado. Conecte-se à internet " +
                                    "uma vez e será salvo para uso offline.",
            failedTitle: "Não foi possível baixar",
            failedMessage: "Algo deu errado durante o download. Tente de novo.",
            loading: "Preparando…",
            retry: "Tentar de novo",
            ok: "OK"
        ),
        "ru": SYSContentNoticeText(
            needsInternetTitle: "Нужен интернет один раз",
            needsInternetMessage: "Это ещё не загружено. Подключись к интернету один " +
                                    "раз, и оно сохранится для работы без сети.",
            failedTitle: "Не удалось загрузить",
            failedMessage: "При загрузке что-то пошло не так. Попробуй ещё раз.",
            loading: "Подготовка…",
            retry: "Повторить",
            ok: "OK"
        ),
        "th": SYSContentNoticeText(
            needsInternetTitle: "ต้องใช้อินเทอร์เน็ตหนึ่งครั้ง",
            needsInternetMessage: "ยังไม่ได้ดาวน์โหลด " +
                                    "เชื่อมต่ออินเทอร์เน็ตหนึ่งครั้ง แล้วจะบันทึกไว้ใช้แบบออฟไลน์",
            failedTitle: "ดาวน์โหลดไม่ได้",
            failedMessage: "เกิดข้อผิดพลาดขณะดาวน์โหลด โปรดลองอีกครั้ง",
            loading: "กำลังเตรียม…",
            retry: "ลองอีกครั้ง",
            ok: "ตกลง"
        ),
        "tr": SYSContentNoticeText(
            needsInternetTitle: "Bir kez internet gerekli",
            needsInternetMessage: "Bu henüz indirilmedi. Bir kez internete bağlan, " +
                                    "çevrimdışı kullanım için kaydedilecek.",
            failedTitle: "İndirilemedi",
            failedMessage: "İndirirken bir sorun oluştu. Lütfen tekrar dene.",
            loading: "Hazırlanıyor…",
            retry: "Tekrar dene",
            ok: "Tamam"
        ),
        "vi": SYSContentNoticeText(
            needsInternetTitle: "Cần internet một lần",
            needsInternetMessage: "Mục này chưa được tải xuống. Hãy kết nối internet một lần " +
                                    "và nó sẽ được lưu để dùng khi không có mạng.",
            failedTitle: "Không tải xuống được",
            failedMessage: "Đã xảy ra lỗi khi tải xuống. Vui lòng thử lại.",
            loading: "Đang chuẩn bị…",
            retry: "Thử lại",
            ok: "OK"
        ),
        "zh-Hans": SYSContentNoticeText(
            needsInternetTitle: "需要联网一次",
            needsInternetMessage: "这项内容还没有下载。联网一次后，它会被保存下来，供离线使用。",
            failedTitle: "无法下载",
            failedMessage: "下载时出了点问题，请重试。",
            loading: "正在准备…",
            retry: "重试",
            ok: "好"
        ),
        "zh-Hant": SYSContentNoticeText(
            needsInternetTitle: "需要連線一次",
            needsInternetMessage: "這項內容尚未下載。連線一次後，就會儲存下來供離線使用。",
            failedTitle: "無法下載",
            failedMessage: "下載時發生問題，請再試一次。",
            loading: "正在準備…",
            retry: "重試",
            ok: "好"
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
