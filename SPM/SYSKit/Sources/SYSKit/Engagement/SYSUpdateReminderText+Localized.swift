import Foundation

extension SYSUpdateReminderText {
    /// The reminder in the first of the given languages that has a translation, English otherwise.
    public static func forLanguages(_ languages: [String] = Locale.preferredLanguages) -> SYSUpdateReminderText {
        SYSLocale.match(translations, for: languages) ?? SYSUpdateReminderText()
    }

    static let translations: [String: SYSUpdateReminderText] = [
        "en": SYSUpdateReminderText(
            title: "Update available",
            message: "A newer version is out with improvements and fixes.",
            update: "Update",
            skip: "Skip this version"
        ),
        "ar": SYSUpdateReminderText(
            title: "تحديث متاح",
            message: "يتوفر إصدار أحدث بتحسينات وإصلاحات.",
            update: "تحديث",
            skip: "تخطي هذا الإصدار"
        ),
        "de": SYSUpdateReminderText(
            title: "Update verfügbar",
            message: "Eine neuere Version mit Verbesserungen und Fehlerbehebungen ist da.",
            update: "Aktualisieren",
            skip: "Diese Version überspringen"
        ),
        "es": SYSUpdateReminderText(
            title: "Actualización disponible",
            message: "Hay una versión más reciente con mejoras y correcciones.",
            update: "Actualizar",
            skip: "Omitir esta versión"
        ),
        "fr": SYSUpdateReminderText(
            title: "Mise à jour disponible",
            message: "Une version plus récente est disponible, avec des améliorations et des corrections.",
            update: "Mettre à jour",
            skip: "Ignorer cette version"
        ),
        "hi": SYSUpdateReminderText(
            title: "अपडेट उपलब्ध है",
            message: "सुधारों और फिक्स के साथ नया वर्ज़न आ गया है।",
            update: "अपडेट करें",
            skip: "इस वर्ज़न को छोड़ें"
        ),
        "id": SYSUpdateReminderText(
            title: "Pembaruan tersedia",
            message: "Versi yang lebih baru telah hadir dengan peningkatan dan perbaikan.",
            update: "Perbarui",
            skip: "Lewati versi ini"
        ),
        "it": SYSUpdateReminderText(
            title: "Aggiornamento disponibile",
            message: "È disponibile una versione più recente con miglioramenti e correzioni.",
            update: "Aggiorna",
            skip: "Salta questa versione"
        ),
        "ja": SYSUpdateReminderText(
            title: "アップデートがあります",
            message: "改善と修正を含む新しいバージョンが公開されています。",
            update: "アップデート",
            skip: "このバージョンをスキップ"
        ),
        "ko": SYSUpdateReminderText(
            title: "업데이트 가능",
            message: "개선 사항과 수정이 포함된 새 버전이 나왔습니다.",
            update: "업데이트",
            skip: "이 버전 건너뛰기"
        ),
        "nl": SYSUpdateReminderText(
            title: "Update beschikbaar",
            message: "Er is een nieuwere versie met verbeteringen en reparaties.",
            update: "Updaten",
            skip: "Deze versie overslaan"
        ),
        "pl": SYSUpdateReminderText(
            title: "Dostępna aktualizacja",
            message: "Dostępna jest nowsza wersja z ulepszeniami i poprawkami.",
            update: "Aktualizuj",
            skip: "Pomiń tę wersję"
        ),
        "pt": SYSUpdateReminderText(
            title: "Atualização disponível",
            message: "Há uma versão mais recente com melhorias e correções.",
            update: "Atualizar",
            skip: "Ignorar esta versão"
        ),
        "ru": SYSUpdateReminderText(
            title: "Доступно обновление",
            message: "Вышла новая версия с улучшениями и исправлениями.",
            update: "Обновить",
            skip: "Пропустить эту версию"
        ),
        "th": SYSUpdateReminderText(
            title: "มีอัปเดตใหม่",
            message: "มีเวอร์ชันใหม่พร้อมการปรับปรุงและแก้ไข",
            update: "อัปเดต",
            skip: "ข้ามเวอร์ชันนี้"
        ),
        "tr": SYSUpdateReminderText(
            title: "Güncelleme mevcut",
            message: "İyileştirmeler ve düzeltmeler içeren yeni bir sürüm çıktı.",
            update: "Güncelle",
            skip: "Bu sürümü atla"
        ),
        "vi": SYSUpdateReminderText(
            title: "Có bản cập nhật",
            message: "Đã có phiên bản mới với nhiều cải tiến và bản sửa lỗi.",
            update: "Cập nhật",
            skip: "Bỏ qua phiên bản này"
        ),
        "zh-hans": SYSUpdateReminderText(
            title: "有可用更新",
            message: "新版本已发布，包含改进与修复。",
            update: "更新",
            skip: "跳过此版本"
        ),
        "zh-hant": SYSUpdateReminderText(
            title: "有可用更新",
            message: "新版本已推出，包含改進與修正。",
            update: "更新",
            skip: "略過此版本"
        ),
        "gu": SYSUpdateReminderText(
            title: "અપડેટ ઉપલબ્ધ છે",
            message: "સુધારા અને ફિક્સ સાથે નવું વર્ઝન આવી ગયું છે.",
            update: "અપડેટ કરો",
            skip: "આ વર્ઝન છોડો"
        ),
        "bn": SYSUpdateReminderText(
            title: "আপডেট পাওয়া যাচ্ছে",
            message: "উন্নতি ও ফিক্সসহ নতুন সংস্করণ এসেছে।",
            update: "আপডেট করুন",
            skip: "এই সংস্করণ বাদ দিন"
        ),
        "mr": SYSUpdateReminderText(
            title: "अपडेट उपलब्ध आहे",
            message: "सुधारणा आणि दुरुस्त्यांसह नवीन आवृत्ती आली आहे.",
            update: "अपडेट करा",
            skip: "ही आवृत्ती वगळा"
        ),
        "kn": SYSUpdateReminderText(
            title: "ಅಪ್ಡೇಟ್ ಲಭ್ಯವಿದೆ",
            message: "ಸುಧಾರಣೆಗಳು ಮತ್ತು ಪರಿಹಾರಗಳೊಂದಿಗೆ ಹೊಸ ಆವೃತ್ತಿ ಬಂದಿದೆ.",
            update: "ಅಪ್ಡೇಟ್ ಮಾಡಿ",
            skip: "ಈ ಆವೃತ್ತಿಯನ್ನು ಬಿಟ್ಟುಬಿಡಿ"
        ),
        "ml": SYSUpdateReminderText(
            title: "അപ്ഡേറ്റ് ലഭ്യമാണ്",
            message: "മെച്ചപ്പെടുത്തലുകളും തിരുത്തലുകളുമായി പുതിയ പതിപ്പ് എത്തി.",
            update: "അപ്ഡേറ്റ് ചെയ്യുക",
            skip: "ഈ പതിപ്പ് ഒഴിവാക്കുക"
        ),
        "or": SYSUpdateReminderText(
            title: "ଅପଡେଟ୍ ଉପଲବ୍ଧ",
            message: "ଉନ୍ନତି ଓ ସଂଶୋଧନ ସହିତ ନୂଆ ସଂସ୍କରଣ ଆସିଛି।",
            update: "ଅପଡେଟ୍ କରନ୍ତୁ",
            skip: "ଏହି ସଂସ୍କରଣ ଛାଡ଼ନ୍ତୁ"
        ),
        "ta": SYSUpdateReminderText(
            title: "புதுப்பிப்பு கிடைக்கிறது",
            message: "மேம்பாடுகளும் திருத்தங்களும் கொண்ட புதிய பதிப்பு வந்துள்ளது.",
            update: "புதுப்பி",
            skip: "இந்தப் பதிப்பைத் தவிர்"
        ),
        "te": SYSUpdateReminderText(
            title: "అప్డేట్ అందుబాటులో ఉంది",
            message: "మెరుగుదలలు, సవరణలతో కొత్త వెర్షన్ వచ్చింది.",
            update: "అప్డేట్ చేయండి",
            skip: "ఈ వెర్షన్ను దాటవేయండి"
        )
    ]
}
