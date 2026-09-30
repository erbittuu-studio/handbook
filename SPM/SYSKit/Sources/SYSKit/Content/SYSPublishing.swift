/// Something a manifest can mark as not live yet.
///
/// The field itself has to live in each app's own item type — no two apps'
/// manifests are shaped alike, and SYSKit inventing a manifest shape would be
/// exactly the mistake this package exists to avoid elsewhere. What every app
/// shares is the one rule for what to do with it, which is what this holds.
public protocol SYSPublishable {
    var isPublished: Bool { get }
}

/// Previewing draft content without a second server.
///
/// A Debug build shows everything, published or not; a Release build shows
/// only what's published. Staging a change is publishing it with
/// `isPublished: false` and deploying normally — the same pipeline, the same
/// URL, real users never see it, and a developer's own Debug build does. No
/// second Hosting site, no environment switch to get wrong.
public enum SYSPublishing {
    #if DEBUG
    public static let isDebugBuild = true
    #else
    public static let isDebugBuild = false
    #endif

    /// Filters `items` down to what this build should show — call this once,
    /// right after a manifest is decoded, and use the result everywhere else
    /// a list of items is needed (what's displayed, what's tracked, what's
    /// downloaded). A production build that skips this and downloads
    /// everything the manifest lists has fetched draft content it will never
    /// show — SYSPublishing.visible gates the download, not only the display.
    ///
    /// `includeUnpublished` defaults to whether this is a Debug build, so a
    /// real call site never has to pass it — it exists as a parameter at all
    /// so tests can exercise both branches without needing a Release build.
    public static func visible<T: SYSPublishable>(
        _ items: [T],
        includeUnpublished: Bool = isDebugBuild
    ) -> [T] {
        includeUnpublished ? items : items.filter(\.isPublished)
    }
}
