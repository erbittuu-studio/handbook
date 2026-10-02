import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum SYSCrypto {
    enum CryptoError: Error, Equatable, Sendable {
        case unavailable
        case malformedBlob
        case authenticationFailed
    }

    static func deriveKey(appStoreID: String) -> Data {
        SYSHash.sha256(Data(appStoreID.utf8))
    }

    static func decrypt(_ blob: Data, appStoreID: String) throws -> Data {
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
