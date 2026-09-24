import XCTest
@testable import SYSKit

// MARK: - Version

final class SYSVersionTests: XCTestCase {
    /// The reason this type exists: string comparison sorts "1.10.0" below
    /// "1.9.0", which behaves correctly until a minor reaches double digits.
    func testDoubleDigitMinorIsNotSortedAsText() {
        XCTAssertEqual(SYSVersion.compare("1.10.0", "1.9.0"), .orderedDescending)
        XCTAssertTrue(SYSVersion.isOlder("1.9.0", than: "1.10.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(SYSVersion.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(SYSVersion.compare("2", "2.0.0"), .orderedSame)
    }

    func testOrdering() {
        XCTAssertEqual(SYSVersion.compare("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(SYSVersion.compare("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(SYSVersion.compare("3.4.5", "3.4.5"), .orderedSame)
    }

    func testNonNumericComponentsDoNotCrash() {
        XCTAssertEqual(SYSVersion.compare("1.x.0", "1.0.0"), .orderedSame)
    }
}

// MARK: - Config decoding

final class SYSConfigDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> SYSConfigData {
        try JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8))
    }

    /// A config that fails to decode is a config that can no longer be fixed
    /// remotely, so every field must be optional.
    func testEmptyObjectDecodes() throws {
        let config = try decode("{}")
        XCTAssertNil(config.version)
        XCTAssertNil(config.flags)
    }

    func testUnknownKeysAreIgnored() throws {
        let config = try decode(#"{"version":2,"somethingAddedLater":{"a":1}}"#)
        XCTAssertEqual(config.version, 2)
    }

    func testLocalisedMessageResolvesByLanguage() throws {
        let config = try decode(#"{"update":{"message":{"en":"Update","hi":"अपडेट"}}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["hi"]), "अपडेट")
        XCTAssertEqual(config.update?.message?.resolved(for: ["en"]), "Update")
    }

    /// An unsupported language should fall back rather than show nothing.
    func testLocalisedMessageFallsBackToEnglish() throws {
        let config = try decode(#"{"update":{"message":{"en":"Update","hi":"अपडेट"}}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["fr"]), "Update")
    }

    /// Older configs wrote a bare string; those must keep working.
    func testBareStringMessageStillDecodes() throws {
        let config = try decode(#"{"update":{"message":"Plain text"}}"#)
        XCTAssertEqual(config.update?.message?.resolved(for: ["en"]), "Plain text")
    }

    func testAppSectionHoldsMixedTypes() throws {
        let config = try decode(#"{"app":{"endpoint":"/packs","max":12,"beta":true}}"#)
        XCTAssertEqual(config.app?["endpoint"]?.stringValue, "/packs")
        XCTAssertEqual(config.app?["max"]?.intValue, 12)
        XCTAssertEqual(config.app?["beta"]?.boolValue, true)
    }
}

// MARK: - Update gates

final class SYSUpdateTests: XCTestCase {
    private func config(_ json: String, version: String) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(version: version))
        // Decoding a compile-time literal fixture; cannot fail.
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    func testBelowMinimumIsRequired() {
        let sut = config(#"{"update":{"minimumVersion":"2.0.0"}}"#, version: "1.9.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .required)
    }

    func testBelowRecommendedIsRecommended() {
        let sut = config(#"{"update":{"minimumVersion":"1.0.0","recommendedVersion":"2.0.0"}}"#, version: "1.5.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .recommended)
    }

    func testCurrentVersionIsFine() {
        let sut = config(#"{"update":{"minimumVersion":"1.0.0","recommendedVersion":"1.5.0"}}"#, version: "1.5.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    /// Double-digit minors are exactly where a string comparison would wrongly
    /// block every user.
    func testDoubleDigitMinorIsNotWronglyBlocked() {
        let sut = config(#"{"update":{"minimumVersion":"1.9.0"}}"#, version: "1.10.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    func testNoUpdateSectionMeansNoGate() {
        let sut = config("{}", version: "1.0.0")
        XCTAssertEqual(SYSUpdate.status(config: sut), .none)
    }

    func testMaintenanceOnlyWhenExplicitlyEnabled() {
        XCTAssertFalse(SYSMaintenance.isActive(config: config("{}", version: "1.0.0")))
        XCTAssertFalse(SYSMaintenance.isActive(config: config(#"{"maintenance":{"enabled":false}}"#, version: "1.0.0")))
        XCTAssertTrue(SYSMaintenance.isActive(config: config(#"{"maintenance":{"enabled":true}}"#, version: "1.0.0")))
    }
}

// MARK: - Network helpers

final class SYSNetworkTests: XCTestCase {
    /// Storage returns 404 for an unescaped path — slashes must be %2F.
    func testStorageURLEncodesSlashes() {
        let url = SYSNetwork.storageURL(bucket: "demo.firebasestorage.app", path: "packs/animals.zip")
        XCTAssertEqual(
            url?.absoluteString,
            "https://firebasestorage.googleapis.com/v0/b/demo.firebasestorage.app/o/packs%2Fanimals.zip?alt=media"
        )
    }

    func testBackoffGrows() {
        XCTAssertLessThan(SYSNetwork.backoff(1), SYSNetwork.backoff(2))
        XCTAssertLessThan(SYSNetwork.backoff(2), SYSNetwork.backoff(3))
    }
}
