import Foundation

/// The app's own links, scheme://kind/id: a scheme check for .onOpenURL and the kind and id split out of it.
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

    public struct Target: Equatable {
        public let kind: String
        public let id: String?

        public init(kind: String, id: String?) {
            self.kind = kind
            self.id = id
        }
    }

    public static func target(of url: URL, scheme: String) -> Target? {
        guard matches(url, scheme: scheme), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let id = url.pathComponents.first { $0 != "/" }
        return Target(kind: host, id: id)
    }

    public static func target(of url: URL, bundle: Bundle = .main) -> Target? {
        scheme(bundle: bundle).flatMap { target(of: url, scheme: $0) }
    }

    static func components(_ url: URL, expectingScheme scheme: String) -> URLComponents? {
        guard matches(url, scheme: scheme) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: true)
    }
}
