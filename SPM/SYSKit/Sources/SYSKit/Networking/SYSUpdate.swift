import Foundation

enum SYSUpdateStatus: Equatable {
    case none
    case recommended
    case required
}

enum SYSUpdate {
    static var status: SYSUpdateStatus { status(config: .shared) }

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
