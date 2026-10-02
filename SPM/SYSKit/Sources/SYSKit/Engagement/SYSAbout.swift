import Foundation

/// Developer identity text every app in this portfolio shows the same way — the same support address, the same footer cr...
public enum SYSAbout {
    static let developer = "Utsav Patel"

    public static func appName(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }

    static var supportEmail: String { SYSConfig.shared.data.supportEmail ?? "utsavhacker@gmail.com" }

    static let credit = "Made with ❤️ by Utsav from 🇮🇳"
}
