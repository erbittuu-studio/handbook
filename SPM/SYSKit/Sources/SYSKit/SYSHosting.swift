import Foundation

/// Where this app's hosted files live, worked out rather than configured.
///
/// Every app's content lives under one shared root on GitHub — `baseURL` below
/// — in its own folder named by `SYSContentID` in the app's Info.plist. Apps on
/// a custom domain call `setContentURL(_:)` before startup instead; everything
/// else gets it for free.
///
/// **Debug builds prefer a local site if one is staged.** Hosted content reaches
/// every installed copy of an app within a minute of a deploy, with no review in
/// between — so "try a change and see" and "publish to everyone" were the same
/// action, and the only way to look at an edit was to ship it. A debug build now
/// reads the staged `Hosting/Content` straight off disk instead. See `localContentURL`.
public enum SYSHosting {
    private static var override: URL?
    private static var cachedContentID: String??

    /// Point every hosted lookup somewhere else — a custom domain, or a staging
    /// site. Call before `SYSBootstrap.start`.
    public static func setContentURL(_ url: URL?) {
        override = url
    }

    /// The shared root every app's content lives under. One string for the
    /// whole portfolio, not per app.
    public static let baseURL = "https://raw.githubusercontent.com/erbittuu-studio/handbook/main/content"

    /// This app's folder under `baseURL`, e.g. `"abclearning"` — from
    /// `SYSContentID` in Info.plist, or nil if the app hasn't set one.
    public static func contentID(bundle: Bundle = .main) -> String? {
        if let cached = cachedContentID { return cached }

        let value = bundle.object(forInfoDictionaryKey: "SYSContentID") as? String
        cachedContentID = value
        if value == nil {
            SYSLogger.info("hosting: no SYSContentID in Info.plist — set the site URL explicitly")
        }
        return value
    }

    /// The content root, e.g. `https://raw.githubusercontent.com/.../content/abclearning/`.
    ///
    /// An explicit `setContentURL` always wins. Failing that, a debug build takes a
    /// staged local site if it finds one, and only then falls back to the live
    /// one — so a release build cannot reach the local branch at all: it is not
    /// compiled into the binary.
    ///
    /// Trailing slash on purpose: `SYSConfig.url(_:)` resolves relative paths
    /// (`"Web/support.html"`) against this, and a base without one drops the
    /// last path component instead of appending to it.
    public static func contentURL(bundle: Bundle = .main) -> URL? {
        if let override { return override }
        #if DEBUG
        if usesLocalContent, let local = localContentURL { return local }
        #endif
        guard let id = contentID(bundle: bundle) else { return nil }
        return URL(string: "\(baseURL)/\(id)/")
    }

    /// Whether a debug build may read a site staged on this machine.
    ///
    /// The one switch between "what is on my disk" and "what is actually
    /// deployed", and it lives here so an app can flip it in a line at launch
    /// without anything in this package needing to know which app it is.
    ///
    /// Defaults off: `SYSPublishing` now covers "try a change and see" against
    /// the same live site (mark it `isPublished: false`), so a build reads what
    /// everyone else does unless something explicitly asks not to. The switch
    /// stays for whenever reading straight off disk is still the right call.
    ///
    /// **Release builds ignore it regardless.** The local branch is inside
    /// `#if DEBUG` and is not compiled into a shipped binary, so an upload
    /// always goes to the network whatever this says. It is declared outside
    /// the `#if` on purpose: an app that sets it should go on compiling when
    /// it is archived, rather than needing its own `#if` around one line.
    public static var usesLocalContent = false

    #if DEBUG
    private static var cachedLocalContent: URL??

    /// A site staged on this machine, or nil.
    ///
    /// Found rather than configured, and by the same reasoning as `projectID`:
    /// the path is not independent information. `#filePath` is this file's
    /// location on the machine that compiled it, so walking up from it reaches
    /// the checkout, and `Hosting/Content` in it is where `build.py` stages the
    /// site. Nothing to set up, nothing to remember to turn off, and nothing in
    /// the app that has to know.
    ///
    /// Simulator only, necessarily — a device cannot read the Mac's disk. To
    /// test local content on hardware the staged site has to be copied into the
    /// app bundle, which is a build phase in the app rather than anything here.
    ///
    /// `SYS_CONTENT_URL` in the scheme's environment overrides the search, for a
    /// staging site or a checkout laid out differently.
    private static var localContentURL: URL? {
        if let cached = cachedLocalContent { return cached }

        let found: URL? = {
            if let raw = ProcessInfo.processInfo.environment["SYS_CONTENT_URL"],
               let url = URL(string: raw) {
                return url
            }
            var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0 ..< 12 {
                let site = dir.appendingPathComponent("Hosting/Content", isDirectory: true)
                if FileManager.default.fileExists(
                    atPath: site.appendingPathComponent("manifest.json").path) {
                    return site
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
            return nil
        }()

        cachedLocalContent = found
        if let found {
            // Loud on purpose. A build quietly reading different content from
            // the one everyone else sees is a bad afternoon.
            SYSLogger.warning("hosting: DEBUG build is reading local content from \(found.path)")
        }
        return found
    }
    #endif

    /// The config file every app serves from its own site.
    public static func configURL(bundle: Bundle = .main) -> URL? {
        contentURL(bundle: bundle)?.appendingPathComponent("config.json")
    }

    /// Testing seam: forget what was read so a different bundle can be used.
    public static func resetForTesting() {
        override = nil
        cachedContentID = nil
        #if DEBUG
        cachedLocalContent = nil
        #endif
    }
}
