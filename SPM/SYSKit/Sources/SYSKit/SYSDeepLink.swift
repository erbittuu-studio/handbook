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

    /// `URLComponents` for `url`, or nil if its scheme doesn't match. Saves
    /// every call site the same two lines: check the scheme, then parse.
    public static func components(_ url: URL, expectingScheme scheme: String) -> URLComponents? {
        guard matches(url, scheme: scheme) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: true)
    }
}
