import Foundation

/// One shared scheme-check for .onOpenURL, nothing more.
public enum SYSDeepLink {
    public static func matches(_ url: URL, scheme: String) -> Bool {
        url.scheme == scheme
    }

    static func scheme(bundle: Bundle = .main) -> String? {
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

    static func components(_ url: URL, expectingScheme scheme: String) -> URLComponents? {
        guard matches(url, scheme: scheme) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: true)
    }
}
