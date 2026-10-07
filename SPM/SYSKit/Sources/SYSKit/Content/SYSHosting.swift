import Foundation

enum SYSHosting {
    private static let overrideURL = SYSLocked<URL?>(nil)
    private static let contentIDCache = SYSLocked<[ObjectIdentifier: String?]>([:])

    static func setContentURL(_ url: URL?) {
        overrideURL.value = url
    }

    static let baseURL = "https://raw.githubusercontent.com/erbittuu-studio/handbook/main/content"

    static func contentID(bundle: Bundle = .main) -> String? {
        let key = ObjectIdentifier(bundle)
        if let cached = contentIDCache.value[key] { return cached }

        let value = bundle.object(forInfoDictionaryKey: "SYSContentID") as? String
        contentIDCache.withLock { $0[key] = value }
        if value == nil {
            SYSLogger.info("hosting: no SYSContentID in Info.plist — set the site URL explicitly")
        }
        return value
    }

    static func contentURL(bundle: Bundle = .main) -> URL? {
        if let override = overrideURL.value { return override }
        #if DEBUG
        if usesLocalContent, let local = localContentURL { return local }
        #endif
        guard let id = contentID(bundle: bundle) else { return nil }
        return URL(string: "\(baseURL)/\(id)/")
    }

    static var usesLocalContent: Bool {
        get { localContentFlag.value }
        set { localContentFlag.value = newValue }
    }

    private static let localContentFlag = SYSLocked(false)

    #if DEBUG
    private static let cachedLocalContent = SYSLocked<URL??>(.none)

    private static var localContentURL: URL? {
        if let cached = cachedLocalContent.value { return cached }

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

        cachedLocalContent.value = found
        if let found {
            SYSLogger.warning("hosting: DEBUG build is reading local content from \(found.path)")
        }
        return found
    }
    #endif

    static func configURL(bundle: Bundle = .main) -> URL? {
        contentURL(bundle: bundle)?.appendingPathComponent("config.json")
    }

    static func resetForTesting() {
        overrideURL.value = nil
        contentIDCache.value = [:]
        #if DEBUG
        cachedLocalContent.value = .none
        #endif
    }
}
