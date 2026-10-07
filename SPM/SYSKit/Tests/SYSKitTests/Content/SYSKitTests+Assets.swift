import XCTest
@testable import SYSKit

// MARK: - SYSContentError / SYSAssetProgress
//
// SYSAssets itself is gone (every app is on SYSContentSync now), but these
// two types are still shared currency — SYSContentSync.prepareRequired and
// SYSBootstrap both speak SYSContentError, and SYSAssetProgress is still
// the progress shape `SYSAssetProgressHandler` carries.

final class SYSContentErrorTests: XCTestCase {
    func testErrorsAreDistinguishable() {
        // The app branches on these to decide whether to offer a retry button.
        XCTAssertNotEqual(SYSContentError.offline, .server(status: 500))
        XCTAssertNotEqual(SYSContentError.corrupt(pack: "a"), .corrupt(pack: "b"))
        XCTAssertEqual(SYSContentError.unsupportedManifest(version: 2), .unsupportedManifest(version: 2))
    }

    func testRetryIsOfferedOnlyWhenItCouldHelp() {
        // Offering "try again" for a fault the server has to fix teaches people
        // to tap it forever.
        XCTAssertTrue(SYSContentError.offline.isRetryable)
        XCTAssertTrue(SYSContentError.server(status: 500).isRetryable)
        XCTAssertTrue(SYSContentError.server(status: 503).isRetryable)

        XCTAssertFalse(SYSContentError.server(status: 404).isRetryable)
        XCTAssertFalse(SYSContentError.server(status: 403).isRetryable)
        XCTAssertFalse(SYSContentError.corrupt(pack: "a").isRetryable)
        XCTAssertFalse(SYSContentError.unsupportedManifest(version: 2).isRetryable)
        XCTAssertFalse(SYSContentError.notConfigured.isRetryable)
    }

    func testDecodeFailureIsNotRetryable() {
        // The bytes are what the server published — asking again returns them
        // again, so a retry button here would lie.
        XCTAssertFalse(SYSContentError.decoding("x").isRetryable)
        XCTAssertFalse(SYSContentError.decoding("x").requiresAppUpdate)
    }

    func testOnlyAStaleBuildAsksForAnUpdate() {
        XCTAssertTrue(SYSContentError.unsupportedManifest(version: 9).requiresAppUpdate)
        XCTAssertFalse(SYSContentError.offline.requiresAppUpdate)
        XCTAssertFalse(SYSContentError.corrupt(pack: "a").requiresAppUpdate)
    }

    func testRetryableAndUpdateAreMutuallyExclusive() {
        // A screen shows one or the other; an error that claims both would render
        // a retry button next to "please update".
        let all: [SYSContentError] = [
            .offline, .server(status: 500), .server(status: 404),
            .corrupt(pack: "a"), .unreadableManifest("x"),
            .unsupportedManifest(version: 2), .missingRequiredPack(id: "a"), .notConfigured
        ]
        for error in all {
            XCTAssertFalse(error.isRetryable && error.requiresAppUpdate, "\(error)")
        }
    }

    func testProgressFractionUsesBytesWhenKnown() {
        let progress = SYSAssetProgress(completedPacks: 1, totalPacks: 4,
                                        bytesDownloaded: 30, totalBytes: 120)
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }

    func testProgressFractionFallsBackToPackCount() {
        // A manifest without byte counts must still produce a sane bar.
        let progress = SYSAssetProgress(completedPacks: 2, totalPacks: 4,
                                        bytesDownloaded: 0, totalBytes: 0)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
    }

    func testProgressFractionIsZeroWhenNothingToDo() {
        let progress = SYSAssetProgress(completedPacks: 0, totalPacks: 0,
                                        bytesDownloaded: 0, totalBytes: 0)
        XCTAssertEqual(progress.fraction, 0)
    }
}

// MARK: - SYSConfigData.app(as:)

private struct TestAppConfig: Decodable, Equatable {
    let maxPages: Int
    let seasonal: Bool
    let nested: Nested
    struct Nested: Decodable, Equatable { let name: String; let sizes: [Int] }
}

final class SYSTypedAccessTests: XCTestCase {
    private func decode(_ json: String) throws -> SYSConfigData {
        try JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8))
    }

    func testAppConfigDecodesIntoTheAppsOwnType() throws {
        // Nested objects and arrays must survive the SYSValue round-trip; if they
        // did not, apps would silently fall back to defaults for half their
        // settings and nothing would say why.
        let config = try decode("""
        {"version":1,"app":{"maxPages":12,"seasonal":true,
         "nested":{"name":"winter","sizes":[1,2,3]}}}
        """)
        XCTAssertEqual(config.app(as: TestAppConfig.self), TestAppConfig(
            maxPages: 12, seasonal: true,
            nested: .init(name: "winter", sizes: [1, 2, 3])
        ))
    }

    func testAppConfigReturnsNilRatherThanFailingOnMismatch() throws {
        let config = try decode(#"{"version":1,"app":{"maxPages":"not a number"}}"#)
        XCTAssertNil(config.app(as: TestAppConfig.self))
    }

    func testAppConfigIsNilWhenSectionAbsent() throws {
        let config = try decode(#"{"version":1}"#)
        XCTAssertNil(config.app(as: TestAppConfig.self))
    }
}

// MARK: - SYSHosting

final class SYSHostingTests: XCTestCase {
    // A site staged on this machine is a configured content URL as far as
    // SYSHosting is concerned, so in a checkout where `build.py site` has been
    // run, "unconfigured" stops being unconfigured and these tests pass or fail
    // depending on whether someone has staged content today. They did: the same
    // three failed in the app and passed in PES, for no reason but that.
    //
    // The debug convenience is switched off for them and restored after, so
    // what is on the developer's disk cannot decide the result.
    /// The test bundle sets no `SYSContentID`, which is exactly the
    /// "app forgot to add it" case.
    static let emptyBundle = Bundle(for: SYSHostingTests.self)

    override func setUp() {
        super.setUp()
        SYSHosting.usesLocalContent = false
        SYSHosting.resetForTesting()
    }

    override func tearDown() {
        SYSHosting.usesLocalContent = true
        SYSHosting.resetForTesting()
        super.tearDown()
    }

    func testExplicitSiteURLWins() {
        SYSHosting.setContentURL(URL(string: "https://staging.example.com")!)
        XCTAssertEqual(SYSHosting.contentURL()?.absoluteString, "https://staging.example.com")
    }

    func testConfigURLHangsOffTheSite() {
        SYSHosting.setContentURL(URL(string: "https://myapp.web.app")!)
        XCTAssertEqual(SYSHosting.configURL()?.absoluteString, "https://myapp.web.app/config.json")
    }

    func testNoContentIDAndNoOverrideMeansNoURL() {
        // Returning nil rather than guessing is what stops an app silently
        // resolving against some other app's content folder.
        XCTAssertNil(SYSHosting.contentID(bundle: Self.emptyBundle))
        XCTAssertNil(SYSHosting.contentURL(bundle: Self.emptyBundle))
        XCTAssertNil(SYSHosting.configURL(bundle: Self.emptyBundle))
    }

    func testContentIDResolvesAgainstTheSharedBaseURL() {
        let bundle = StubBundle(contentID: "abclearning")
        XCTAssertEqual(SYSHosting.contentID(bundle: bundle), "abclearning")
        XCTAssertEqual(SYSHosting.contentURL(bundle: bundle)?.absoluteString, "\(SYSHosting.baseURL)/abclearning/")
        XCTAssertEqual(SYSHosting.configURL(bundle: bundle)?.absoluteString, "\(SYSHosting.baseURL)/abclearning/config.json")
    }

    func testOverrideSurvivesAMissingPlist() {
        SYSHosting.setContentURL(URL(string: "https://custom.domain")!)
        XCTAssertEqual(SYSHosting.contentURL(bundle: Self.emptyBundle)?.absoluteString, "https://custom.domain")
    }

    func testResetClearsTheOverride() {
        SYSHosting.setContentURL(URL(string: "https://custom.domain")!)
        SYSHosting.resetForTesting()
        XCTAssertNil(SYSHosting.contentURL(bundle: Self.emptyBundle))
    }
}

// MARK: - SYSConfig.url(_:)

final class SYSConfigURLTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SYSHosting.usesLocalContent = false
        SYSHosting.resetForTesting()
    }

    override func tearDown() {
        SYSHosting.usesLocalContent = true
        SYSHosting.resetForTesting()
        super.tearDown()
    }

    private func config(_ json: String, contentID: String? = "abclearning") -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(contentID: contentID))
        // Decoding a compile-time literal fixture; cannot fail.
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    func testRelativeURLResolvesAgainstThisAppsContentFolder() {
        let sut = config(#"{"urls":{"support":"Web/support.html"}}"#)
        XCTAssertEqual(sut.url("support")?.absoluteString, "\(SYSHosting.baseURL)/abclearning/Web/support.html")
    }

    func testAbsoluteURLIsUsedAsIs() {
        let sut = config(#"{"urls":{"support":"https://example.com/support.html"}}"#)
        XCTAssertEqual(sut.url("support")?.absoluteString, "https://example.com/support.html")
    }

    func testMissingKeyIsNil() {
        let sut = config(#"{"urls":{}}"#)
        XCTAssertNil(sut.url("support"))
    }
}

// MARK: - SYSAppCatalog / SYSUpdate.storeURL

final class SYSAppCatalogTests: XCTestCase {
    override func tearDown() {
        SYSHosting.resetForTesting()
        super.tearDown()
    }

    private func catalog(contentID: String?, entries: [SYSAppCatalogEntry]) -> SYSAppCatalog {
        let catalog = SYSAppCatalog(bundle: StubBundle(contentID: contentID))
        catalog.applyForTesting(SYSAppCatalogData(version: 1, baseUrl: SYSHosting.baseURL, apps: entries))
        return catalog
    }

    func testThisAppMatchesByContentID() {
        let sut = catalog(contentID: "abclearning", entries: [
            SYSAppCatalogEntry(id: "colorful", name: "Colorful", appStoreUrl: "https://apps.apple.com/colorful"),
            SYSAppCatalogEntry(id: "abclearning", name: "ABC Learning", appStoreUrl: "https://apps.apple.com/abclearning"),
        ])
        XCTAssertEqual(sut.thisApp?.id, "abclearning")
        XCTAssertEqual(sut.thisApp?.appStoreUrl, "https://apps.apple.com/abclearning")
    }

    func testThisAppIsNilWithoutAMatch() {
        let sut = catalog(contentID: "drawing", entries: [
            SYSAppCatalogEntry(id: "colorful", name: "Colorful"),
        ])
        XCTAssertNil(sut.thisApp)
    }

    func testStoreURLReadsFromAlreadyLoadedCatalog() async {
        let sut = catalog(contentID: "abclearning", entries: [
            SYSAppCatalogEntry(id: "abclearning", name: "ABC Learning", appStoreUrl: "https://apps.apple.com/abclearning"),
        ])
        let url = await SYSUpdate.storeURL(catalog: sut)
        XCTAssertEqual(url?.absoluteString, "https://apps.apple.com/abclearning")
    }

    func testStoreURLIsNilWhenEntryHasNoAppStoreURL() async {
        let sut = catalog(contentID: "abclearning", entries: [
            SYSAppCatalogEntry(id: "abclearning", name: "ABC Learning"),
        ])
        let url = await SYSUpdate.storeURL(catalog: sut)
        XCTAssertNil(url)
    }
}
