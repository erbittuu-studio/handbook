import Foundation

/// Developer identity text every app in this portfolio shows the same way —
/// the same support address, the same footer credit. All three apps had
/// this as an identical literal string, hand-copied into each one, which is
/// exactly the kind of fact that quietly drifts the next time it changes in
/// one place and not the other two. One value here instead of three.
///
/// Not a fact about the running app the way `SYSVersion` is — an app is free
/// not to show any of this, or to show its own instead — but where an app
/// does want it, this is the one spelling.
public enum SYSAbout {
    public static let developer = "Utsav Patel"
    public static let supportEmail = "utsavhacker@gmail.com"

    /// Settings-screen footer credit. Emoji and phrasing are the point —
    /// this is a signature, not a fact, so it stays exactly this way rather
    /// than becoming configurable.
    public static let credit = "Made with ❤️ by Utsav from 🇮🇳"
}
