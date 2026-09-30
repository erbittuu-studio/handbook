import Foundation

/// One shared scheme-check for `.onOpenURL`, nothing more.
///
/// A deep link's shape — what the host means, how many path components,
/// what they identify — is app-specific by nature, and stays app-specific
/// here. What was actually repeated across apps was the scheme guard itself,
/// written slightly differently each time, and where a parsed link's target
/// goes next: straight into navigation, which drops it if the app is not
/// ready yet rather than queuing it through a `SYSPendingIntent`.
public enum SYSDeepLink {
    /// Whether `url` is one this app should handle at all.
    public static func matches(_ url: URL, scheme: String) -> Bool {
        url.scheme == scheme
    }

    /// The first URL scheme the app registers in `CFBundleURLTypes`, so the
    /// scheme is written once, in the Info.plist, and never in code.
    public static func scheme(bundle: Bundle = .main) -> String? {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return types?.lazy.compactMap { ($0["CFBundleURLSchemes"] as? [String])?.first }.first
    }

    public static func matches(_ url: URL, bundle: Bundle = .main) -> Bool {
        scheme(bundle: bundle).map { matches(url, scheme: $0) } ?? false
    }

    public static func url(scheme: String, host: String, path: String) -> URL? {
        URL(string: "\(scheme)://\(host)/\(path)")
    }

    public static func url(host: String, path: String, bundle: Bundle = .main) -> URL? {
        scheme(bundle: bundle).flatMap { url(scheme: $0, host: host, path: path) }
    }

    /// `URLComponents` for `url`, or nil if its scheme doesn't match. Saves
    /// every call site the same two lines: check the scheme, then parse.
    public static func components(_ url: URL, expectingScheme scheme: String) -> URLComponents? {
        guard matches(url, scheme: scheme) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: true)
    }
}
