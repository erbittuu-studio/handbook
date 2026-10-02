import Foundation

/// Why the app could not get something it needs from the server.
public enum SYSContentError: Error, Equatable, Sendable {
    case offline
    case server(status: Int)
    case corrupt(pack: String)
    case unreadableManifest(String)
    case unsupportedManifest(version: Int)
    case missingRequiredPack(id: String)
    case notConfigured
    case decoding(String)

    var isRetryable: Bool {
        switch self {
        case .offline:
            return true
        case let .server(status):
            return status >= 500
        case .corrupt, .unreadableManifest, .decoding:
            return false
        case .unsupportedManifest, .missingRequiredPack, .notConfigured:
            return false
        }
    }

    var requiresAppUpdate: Bool {
        if case .unsupportedManifest = self { return true }
        return false
    }
}

/// Progress through a prepareRequired run, for apps that show a bar.
public struct SYSAssetProgress: Equatable, Sendable {
    public let completedPacks: Int
    public let totalPacks: Int
    let bytesDownloaded: Int
    let totalBytes: Int

    public init(completedPacks: Int, totalPacks: Int, bytesDownloaded: Int, totalBytes: Int) {
        self.completedPacks = completedPacks
        self.totalPacks = totalPacks
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        totalBytes > 0
            ? Double(bytesDownloaded) / Double(totalBytes)
            : (totalPacks > 0 ? Double(completedPacks) / Double(totalPacks) : 0)
    }
}
