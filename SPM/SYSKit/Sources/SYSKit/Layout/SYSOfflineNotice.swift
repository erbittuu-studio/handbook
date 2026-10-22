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
        "en": SYSOfflineText(
            title: "You're offline",
            message: "Saved content still works.",
            partial: "Some content is not downloaded yet. Connect once to finish."
        ),
        "hi": SYSOfflineText(
            title: "आप ऑफ़लाइन हैं",
            message: "सहेजी हुई सामग्री अब भी चलती है।",
            partial: "कुछ सामग्री अभी डाउनलोड नहीं हुई है। पूरा करने के लिए एक बार इंटरनेट से जुड़ें।"
        ),
        "gu": SYSOfflineText(
            title: "તમે ઓફલાઇન છો",
            message: "સાચવેલી સામગ્રી હજી પણ ચાલે છે.",
            partial: "કેટલી સામગ્રી હજી ડાઉનલોડ થઈ નથી. પૂરી કરવા એક વાર ઇન્ટરનેટ સાથે જોડાઓ."
        ),
        "ar": SYSOfflineText(
            title: "أنت غير متصل بالإنترنت",
            message: "المحتوى المحفوظ ما زال يعمل.",
            partial: "بعض المحتوى لم يتم تنزيله بعد. اتصل بالإنترنت مرة واحدة لإكماله."
        ),
        "de": SYSOfflineText(
            title: "Du bist offline",
            message: "Gespeicherte Inhalte funktionieren weiterhin.",
            partial: "Einige Inhalte sind noch nicht geladen. Verbinde dich " +
                         "einmal mit dem Internet, um sie fertig zu laden."
        ),
        "es": SYSOfflineText(
            title: "Sin conexión",
            message: "El contenido guardado sigue funcionando.",
            partial: "Parte del contenido aún no se ha descargado. Conéctate una vez para terminar."
        ),
        "fr": SYSOfflineText(
            title: "Tu es hors connexion",
            message: "Le contenu enregistré fonctionne toujours.",
            partial: "Une partie du contenu n'est pas encore téléchargée. " +
                         "Connecte-toi une fois pour terminer."
        ),
        "id": SYSOfflineText(
            title: "Kamu sedang offline",
            message: "Konten yang tersimpan tetap berfungsi.",
            partial: "Sebagian konten belum diunduh. Sambungkan ke internet sekali untuk menyelesaikannya."
        ),
        "it": SYSOfflineText(
            title: "Sei offline",
            message: "I contenuti salvati funzionano ancora.",
            partial: "Alcuni contenuti non sono ancora stati scaricati. Collegati una volta per completare."
        ),
        "ja": SYSOfflineText(
            title: "オフラインです",
            message: "保存済みのコンテンツは引き続き使えます。",
            partial: "まだダウンロードされていないコンテンツがあります。一度接続して完了させてください。"
        ),
        "ko": SYSOfflineText(
            title: "오프라인 상태예요",
            message: "저장된 콘텐츠는 계속 사용할 수 있어요.",
            partial: "아직 다운로드되지 않은 콘텐츠가 있어요. 한 번 연결해서 완료해 주세요."
        ),
        "nl": SYSOfflineText(
            title: "Je bent offline",
            message: "Bewaarde inhoud werkt nog steeds.",
            partial: "Een deel van de inhoud is nog niet gedownload. Maak " +
                         "één keer verbinding om het af te maken."
        ),
        "pl": SYSOfflineText(
            title: "Jesteś offline",
            message: "Zapisane treści nadal działają.",
            partial: "Część treści nie została jeszcze pobrana. Połącz się raz, aby dokończyć."
        ),
        "pt-BR": SYSOfflineText(
            title: "Você está offline",
            message: "O conteúdo salvo continua funcionando.",
            partial: "Parte do conteúdo ainda não foi baixada. Conecte-se uma vez para concluir."
        ),
        "ru": SYSOfflineText(
            title: "Нет подключения к интернету",
            message: "Сохранённое содержимое по-прежнему работает.",
            partial: "Часть содержимого ещё не загружена. Подключись один раз, чтобы завершить."
        ),
        "th": SYSOfflineText(
            title: "คุณออฟไลน์อยู่",
            message: "เนื้อหาที่บันทึกไว้ยังใช้งานได้",
            partial: "เนื้อหาบางส่วนยังไม่ได้ดาวน์โหลด เชื่อมต่ออินเทอร์เน็ตหนึ่งครั้งเพื่อให้เสร็จ"
        ),
        "tr": SYSOfflineText(
            title: "Çevrimdışısın",
            message: "Kaydedilen içerik çalışmaya devam eder.",
            partial: "Bazı içerikler henüz indirilmedi. Tamamlamak için bir kez internete bağlan."
        ),
        "vi": SYSOfflineText(
            title: "Bạn đang ngoại tuyến",
            message: "Nội dung đã lưu vẫn dùng được.",
            partial: "Một số nội dung chưa được tải xuống. Hãy kết nối một lần để hoàn tất."
        ),
        "zh-Hans": SYSOfflineText(
            title: "你已离线",
            message: "已保存的内容仍然可用。",
            partial: "部分内容尚未下载。联网一次即可完成。"
        ),
        "zh-Hant": SYSOfflineText(
            title: "你已離線",
            message: "已儲存的內容仍可使用。",
            partial: "部分內容尚未下載。連線一次即可完成。"
        )
    ]
}

private struct SYSConnectionIndicator: ViewModifier {
    private enum Mark { case offline, online }

    private struct Trigger: Hashable {
        var online: Bool
        var wake: Int
    }

    let text: SYSOfflineText
    @ObservedObject private var connectivity = SYSConnectivity.shared
    @ObservedObject private var readiness = SYSContentReadiness.shared
    @State private var mark: Mark?
    @State private var wake = 0
    @State private var wasOffline = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let mark {
                    badge(mark)
                        .padding(.bottom, SYSSize.touch + SYSSpace.md)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
            .task(id: Trigger(online: connectivity.isOnline, wake: wake)) { await react() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                if !connectivity.isOnline { wake += 1 }
            }
    }

    private func react() async {
        if connectivity.isOnline {
            guard wasOffline else { return }
            wasOffline = false
            await pop(.online, after: 0)
        } else {
            wasOffline = true
            await pop(.offline, after: SYSTiming.relaxed * 4)
        }
    }

    private func pop(_ next: Mark, after delay: TimeInterval) async {
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
        }
        withAnimation(SYSMotion.standard) { mark = next }
        try? await Task.sleep(nanoseconds: UInt64(3 * 1_000_000_000))
        if Task.isCancelled { return }
        withAnimation(SYSMotion.standard) { mark = nil }
    }

    private func badge(_ mark: Mark) -> some View {
        let offline = mark == .offline
        return Image(systemName: offline ? SYSSymbol.offline : "wifi")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(offline ? Color.red : Color.green))
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(offline ? text.title : "")
            .accessibilityHint(offline ? (readiness.missing > 0 ? text.partial : text.message) : "")
    }
}

public extension View {
    /// A small red Wi-Fi-off badge pops in at the bottom centre, above a tab bar, a moment after the connection is lost and hides
    /// after a few seconds; a green Wi-Fi badge does the same when it returns. No words, and it never takes a touch;
    /// VoiceOver reads the offline text.
    /// It pops again each time the app comes back to the foreground while still offline.
    /// `SYSRootedApp` attaches it once at the app root, so every app and screen shows it the same way.
    func sysConnectionIndicator(_ text: SYSOfflineText = .forLanguages()) -> some View {
        modifier(SYSConnectionIndicator(text: text))
    }
}
#endif
