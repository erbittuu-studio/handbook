import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Decrypts packs a site's `publish.py` published — reverses `crypto.py`,
/// its Python counterpart. Decrypt only: SYSKit reads published content, it
/// never publishes any.
///
/// The key is `SHA-256` of this app's own App Store id — every app already
/// knows its own (`SYSHosting.contentID()`), so nothing else has to be
/// configured or stored to compute it back. This is a deterrent against
/// casual scraping of the hosting, not strong protection: nothing can stop
/// someone who reverse-engineers the compiled app itself, since the app has
/// to be able to decrypt its own downloads.
///
/// CryptoKit is Apple-only, and SYSKit builds and tests on Linux with no
/// Xcode (see `SYSHash`) — so, like `SYSZip`'s `.decompressionUnavailable`
/// for the same reason, decrypting is unavailable there. Nothing in this
/// package needs to decrypt for real on Linux; only the actual app build
/// ever does.
public enum SYSCrypto {
    public enum CryptoError: Error, Equatable, Sendable {
        /// No CryptoKit on this platform (Linux). Never hit on a real build.
        case unavailable
        /// Too short to be nonce + ciphertext + tag.
        case malformedBlob
        /// Wrong key, or the bytes were tampered with — GCM's tag caught it.
        case authenticationFailed
    }

    /// `SHA-256(appStoreID)` — see `crypto.py`'s `derive_key`, the same
    /// formula on the publishing side.
    public static func deriveKey(appStoreID: String) -> Data {
        SYSHash.sha256(Data(appStoreID.utf8))
    }

    /// Reverses `crypto.py`'s `encrypt`: `blob` is `nonce(12) + ciphertext +
    /// tag(16)`, one self-contained value. Fails closed — corrupted or
    /// tampered bytes throw `.authenticationFailed` rather than returning
    /// garbage.
    public static func decrypt(_ blob: Data, appStoreID: String) throws -> Data {
        #if canImport(CryptoKit)
        guard blob.count > 12 + 16 else { throw CryptoError.malformedBlob }
        let key = SymmetricKey(data: deriveKey(appStoreID: appStoreID))
        let nonceBytes = blob.prefix(12)
        let tag = blob.suffix(16)
        let ciphertext = blob.dropFirst(12).dropLast(16)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceBytes)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw CryptoError.authenticationFailed
        }
        #else
        throw CryptoError.unavailable
        #endif
    }
}
