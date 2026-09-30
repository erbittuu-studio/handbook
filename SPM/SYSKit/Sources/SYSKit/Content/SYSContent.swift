import Foundation

/// Where the device keeps its copy of the hosted site.
///
/// **The same shape as the site it came from.** The server serves
/// `config.json`, `manifest.json` and `packs/`; the device holds
/// `config.json`, `manifest.json` and `packs/`. One layout, in two places, so
/// "what is deployed" and "what this phone has" can be compared by looking.
///
/// They used to differ for no reason: config sat loose in Application Support
/// while the packs and the manifest were together under a folder named after
/// the type that wrote them. Nothing was wrong with it, and nothing about it
/// told you anything either.
///
/// One place knows this. `SYSConfig` and `SYSAssets` both ask, rather than each
/// deriving a path of its own and drifting.
public enum SYSContent {
    /// `Application Support/Content`, created on first use.
    ///
    /// Excluded from backup, all of it. Every byte in here came from the server
    /// and can come again — backing it up would put a copy of the app's content
    /// in iCloud for every install, to save a download the app is willing to do
    /// anyway. A restored device fetches it exactly as a new one does.
    ///
    /// A child's drawings are **not** in here. They live beside it, they are the
    /// only copy of something nobody can re-fetch, and they are backed up — see
    /// `PageStore` in the app.
    public static func directory(_ fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true)
        let directory = support.appendingPathComponent("Content", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var mutable = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutable.setResourceValues(values)
        }
        return directory
    }

    /// `Content/packs`, where the downloaded bundles land.
    public static func packs(_ fileManager: FileManager = .default) throws -> URL {
        let directory = try self.directory(fileManager).appendingPathComponent("packs",
                                                                               isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// `Content/<name>` — for the two files that sit beside `packs`.
    public static func file(_ name: String, _ fileManager: FileManager = .default) throws -> URL {
        try directory(fileManager).appendingPathComponent(name)
    }
}
