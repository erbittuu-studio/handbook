import Foundation

/// Why the app could not get something it needs from the server.
///
/// Covers all three: the config, the manifest, and the packs. They fail in the
/// same ways and, to the person holding the phone, they are one situation —
/// "we could not reach the server" — not three. One type means one mapping from
/// error to sentence in the app, and one answer to whether a retry is honest.
public enum SYSContentError: Error, Equatable, Sendable {
    /// No usable network. Retrying is the right offer.
    case offline
    /// The server answered, and the answer was a failure.
    case server(status: Int)
    /// Downloaded bytes did not match the hash the manifest published.
    case corrupt(pack: String)
    /// The manifest could not be read.
    case unreadableManifest(String)
    /// The manifest is a newer format than this build understands.
    case unsupportedManifest(version: Int)
    /// A required pack is not in the manifest at all.
    case missingRequiredPack(id: String)
    /// `configure` was never called, or nothing points at any content at all.
    case notConfigured
    /// The pack arrived and did not match the type the app asked for.
    case decoding(String)

    /// Whether offering "try again" is honest.
    ///
    /// Apps kept deciding this individually and would eventually disagree — a
    /// retry button on a 404 re-fetches the same 404, and on a hash mismatch it
    /// re-downloads the same bad bytes. Both need a fix on the server, not
    /// another tap.
    public var isRetryable: Bool {
        switch self {
        case .offline:
            return true
        case let .server(status):
            // 5xx is usually transient; 4xx will answer identically next time.
            return status >= 500
        case .corrupt, .unreadableManifest, .decoding:
            // The bytes are what the server published; asking again gets them
            // again. Either the app or the pack has to change.
            return false
        case .unsupportedManifest, .missingRequiredPack, .notConfigured:
            return false
        }
    }

    /// Whether the user needs a newer build rather than another attempt.
    public var requiresAppUpdate: Bool {
        if case .unsupportedManifest = self { return true }
        return false
    }
}

/// Progress through a `prepareRequired` run, for apps that show a bar.
public struct SYSAssetProgress: Equatable, Sendable {
    public let completedPacks: Int
    public let totalPacks: Int
    public let bytesDownloaded: Int
    public let totalBytes: Int

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
