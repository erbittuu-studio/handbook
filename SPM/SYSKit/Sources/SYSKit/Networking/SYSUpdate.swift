import Foundation

enum SYSUpdateStatus: Equatable {
    case none
    case recommended
    case required
}

/// A newer app version the remote config recommends but does not require.
public struct SYSRecommendedUpdate: Equatable, Sendable {
    public let version: String
    public let message: String?
}

/// What the remote config says about updating the running version; a required update is handled at launch.
public enum SYSUpdate {
    static var status: SYSUpdateStatus { status(config: .shared) }

    public static var recommended: SYSRecommendedUpdate? {
        recommended(config: .shared)
    }

    static func recommended(config: SYSConfig) -> SYSRecommendedUpdate? {
        guard status(config: config) == .recommended,
              let version = config.data.update?.recommendedVersion else { return nil }
        return SYSRecommendedUpdate(version: version, message: message(config: config))
    }

    static func status(config: SYSConfig) -> SYSUpdateStatus {
        let current = config.currentVersion

        if let minimum = config.data.update?.minimumVersion,
           SYSVersion.isOlder(current, than: minimum) {
            return .required
        }
        if let recommended = config.data.update?.recommendedVersion,
           SYSVersion.isOlder(current, than: recommended) {
            return .recommended
        }
        return .none
    }

    static func message(config: SYSConfig = .shared) -> String? {
        config.data.update?.message?.resolved()
    }

    static func storeURL(catalog: SYSAppCatalog = .shared) async -> URL? {
        catalog.load()
        if catalog.thisApp == nil {
            _ = await catalog.refresh()
        }
        guard let raw = catalog.thisApp?.appStoreUrl else { return nil }
        return URL(string: raw)
    }
}

enum SYSMaintenance {
    static func isActive(config: SYSConfig = .shared) -> Bool {
        config.data.maintenance?.enabled == true
    }

    static func message(config: SYSConfig = .shared) -> String? {
        config.data.maintenance?.message?.resolved()
    }
}

enum SYSWhatsNew {
    private static let seenKey = SYSSettingsKey<String?>("sys.whatsNew.seenVersion", default: nil)

    static func notes(config: SYSConfig = .shared) -> [String]? {
        guard let perVersion = config.data.whatsNew?[config.currentVersion] else { return nil }
        return SYSLocale.match(perVersion.filter { !$0.value.isEmpty })
    }

    static func shouldShow(config: SYSConfig = .shared) -> Bool {
        guard notes(config: config) != nil else { return false }
        return SYSSettings.shared[seenKey] != config.currentVersion
    }

    static func markSeen(config: SYSConfig = .shared) {
        SYSSettings.shared[seenKey] = config.currentVersion
    }
}
