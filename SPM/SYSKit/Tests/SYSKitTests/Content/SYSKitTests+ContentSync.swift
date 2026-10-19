import XCTest
@testable import SYSKit
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - SYSContentSync

private struct FakeContentItem: SYSContentItem, Equatable {
    let id: String
    let bundle: String
    let checksum: String?
    let isPublished: Bool
}

@MainActor
final class SYSContentSyncTests: XCTestCase {
    /// A random storage folder and key pair per test — this exercises the
    /// exact same `SYSSettings.shared` a real app uses (there is no
    /// injectable instance), so uniqueness is what keeps two test runs, or a
    /// test and a real app on the same machine, from ever sharing a key.
    private func makeSync(manifestName: String = "content") -> SYSContentSync<FakeContentItem> {
        let suffix = UUID().uuidString
        let dataVersionKey = SYSSettingsKey<Int>("test.dataVersion.\(suffix)", default: 0)
        let itemChecksumMapKey = SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(suffix)", default: [:])
        let sync = SYSContentSync<FakeContentItem>(
            manifestName: manifestName,
            storageFolder: "sysContentSyncTests-\(suffix)",
            dataVersionKey: dataVersionKey,
            itemChecksumMapKey: itemChecksumMapKey)
        addTeardownBlock {
            sync.clearAllData()
            try? FileManager.default.removeItem(at: sync.rootURL)
        }
        return sync
    }

    func testLoadCachedMarksNothingDownloadedWhenDiskIsEmpty() {
        let sync = makeSync()
        let items = [FakeContentItem(id: "a", bundle: "a.zip", checksum: nil, isPublished: true)]

        sync.loadCached(items)

        XCTAssertEqual(sync.items, items)
        XCTAssertEqual(sync.itemStates["a"], .notDownloaded)
        XCTAssertFalse(sync.hasCachedContent)
    }

    func testClearAllDataResetsStateAndVersion() {
        let sync = makeSync()
        let folder = sync.itemsRoot.appendingPathComponent("a")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: folder.appendingPathComponent("index.json"))
        sync.loadCached([FakeContentItem(id: "a", bundle: "a.zip", checksum: nil, isPublished: true)])
        XCTAssertTrue(sync.hasCachedContent)

        sync.clearAllData()

        XCTAssertFalse(sync.hasCachedContent)
        XCTAssertEqual(sync.dataVersion, 0)
    }

    func testUrlJoinsBaseAndPath() {
        let sync = makeSync()
        sync.configure(baseURL: "https://example.com/content")
        XCTAssertEqual(sync.url(path: "items/a.zip")?.absoluteString, "https://example.com/content/items/a.zip")
    }

    func testUrlStripsALeadingSlashOnThePath() {
        // Some apps' bundle fields are "/packs/x.zip", some are "packs/x.zip"
        // (see the handbook's publish.py files) — both must resolve under
        // this manifest's own root, never one level up from it.
        let sync = makeSync()
        sync.configure(baseURL: "https://example.com/content")
        XCTAssertEqual(sync.url(path: "/packs/a.zip")?.absoluteString, "https://example.com/content/packs/a.zip")
    }

    func testBaseURLDerivesFromContentIDAndManifestName() {
        SYSHosting.usesLocalContent = false
        defer { SYSHosting.usesLocalContent = true; SYSHosting.resetForTesting() }
        SYSHosting.resetForTesting()

        let sync = SYSContentSync<FakeContentItem>(
            manifestName: "festivals",
            storageFolder: "sysContentSyncTests-\(UUID().uuidString)",
            dataVersionKey: SYSSettingsKey<Int>("t.v.\(UUID())", default: 0),
            itemChecksumMapKey: SYSSettingsKey<[String: String]>("t.c.\(UUID())", default: [:]),
            bundle: StubBundle(contentID: "prarthana"))
        addTeardownBlock { sync.clearAllData(); try? FileManager.default.removeItem(at: sync.rootURL) }

        XCTAssertEqual(sync.baseURL, "\(SYSHosting.baseURL)/prarthana/festivals/")
    }
}

// MARK: - SYSContentSync — refresh(), decrypt, non-archive items
//
// CryptoKit-only (Apple platforms) — SYSCrypto.decrypt itself degrades to
// `.unavailable` on Linux (see that file), so there is nothing for these
// specifically to exercise there either.
#if canImport(CryptoKit)

/// Encrypts a fixture the same way `crypto.py`/`SYSCrypto` do, so these
/// tests exercise the real format end to end rather than asserting against
/// a mock. Test-only — production code only ever decrypts (see `SYSCrypto`).
private enum MiniCrypto {
    static func encrypt(_ plaintext: Data, appStoreID: String) throws -> Data {
        let key = SymmetricKey(data: SYSCrypto.deriveKey(appStoreID: appStoreID))
        let nonce = try AES.GCM.Nonce(data: Data(SHA256.hash(data: plaintext)).prefix(12))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        return sealed.combined ?? (nonce.withUnsafeBytes { Data($0) } + sealed.ciphertext + sealed.tag)
    }
}

@MainActor
final class SYSContentSyncRefreshTests: XCTestCase {
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

    private func tempSiteRoot() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSync(manifestName: String = "content", contentID: String? = "test-app") -> SYSContentSync<FakeContentItem> {
        let suffix = UUID().uuidString
        let sync = SYSContentSync<FakeContentItem>(
            manifestName: manifestName,
            storageFolder: "sysContentSyncRefreshTests-\(suffix)",
            dataVersionKey: SYSSettingsKey<Int>("test.dataVersion.\(suffix)", default: 0),
            itemChecksumMapKey: SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(suffix)", default: [:]),
            bundle: StubBundle(contentID: contentID))
        addTeardownBlock {
            sync.clearAllData()
            try? FileManager.default.removeItem(at: sync.rootURL)
        }
        return sync
    }

    /// Writes `<siteRoot>/<manifestName>/manifest.json` plus one encrypted
    /// pack, honoring the leading-slash-or-not convention every app's real
    /// publish.py actually uses.
    private func stageManifest(
        at siteRoot: URL,
        manifestName: String,
        itemID: String,
        bundleFilename: String,
        plaintext: Data,
        contentID: String
    ) throws -> URL {
        let manifestDir = siteRoot.appendingPathComponent(manifestName, isDirectory: true)
        let packsDir = manifestDir.appendingPathComponent("packs", isDirectory: true)
        try FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)

        let encrypted = try MiniCrypto.encrypt(plaintext, appStoreID: contentID)
        let bundlePath = packsDir.appendingPathComponent(bundleFilename)
        try encrypted.write(to: bundlePath)

        let manifest = """
        {"manifestVersion": 1, "generatedAt": null, "items": [
          {"id": "\(itemID)", "bundle": "packs/\(bundleFilename)",
           "checksum": "\(SYSHash.sha256Hex(encrypted))", "isPublished": true}
        ]}
        """
        try manifest.write(to: manifestDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        return manifestDir
    }

    /// Adds a second encrypted item to a manifest `stageManifest` already
    /// wrote — for a test that needs two items with different fates (one
    /// good, one encrypted for the wrong app id).
    private func appendItem(
        id: String,
        plaintext: Data,
        encryptFor contentID: String,
        to manifestDir: URL
    ) throws {
        let bundleFilename = "\(id).zip"
        let encrypted = try MiniCrypto.encrypt(plaintext, appStoreID: contentID)
        try encrypted.write(to: manifestDir.appendingPathComponent("packs/\(bundleFilename)"))

        let checksum = SYSHash.sha256Hex(encrypted)
        let entry = #", {"id": "\#(id)", "bundle": "packs/\#(bundleFilename)", "#
            + #""checksum": "\#(checksum)", "isPublished": true}]}"#
        let manifestPath = manifestDir.appendingPathComponent("manifest.json")
        let manifest = try String(contentsOf: manifestPath, encoding: .utf8)
        try manifest.replacingOccurrences(of: "]}", with: entry)
            .write(to: manifestPath, atomically: true, encoding: .utf8)
    }

    func testRefreshDownloadsDecryptsAndUnzipsAnArchiveItem() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"hello":"world"}"#.utf8))])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                              bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        await sync.refresh()

        XCTAssertEqual(sync.syncState, .ready)
        XCTAssertEqual(sync.itemStates["a"], .downloaded)
        let content = sync.loadFile(itemId: "a", filename: "index.json")
        XCTAssertEqual(content.flatMap { String(data: $0, encoding: .utf8) }, #"{"hello":"world"}"#)
    }

    func testAnArchiveItemWithoutIndexJSONStaysAvailableAfterReload() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "baby_0.svg", contents: Data("<svg/>".utf8))])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "baby",
                              bundleFilename: "baby.zip", plaintext: zip, contentID: "test-app")
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")
        await sync.refresh()

        sync.loadCached(sync.items)

        XCTAssertEqual(sync.itemStates["baby"], .downloaded)
        XCTAssertTrue(sync.hasCachedContent)
    }

    func testFilenamesListsWhatAnArchiveItemUnzippedTo() async throws {
        // Colorful's case exactly: page order is just the sorted filenames
        // the zip happened to contain, nothing named in the manifest.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([
            .init(path: "baby_1.svg", contents: Data("<svg/>".utf8)),
            .init(path: "baby_0.svg", contents: Data("<svg/>".utf8))
        ])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "baby",
                              bundleFilename: "baby.zip", plaintext: zip, contentID: "test-app")
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        XCTAssertEqual(sync.filenames(itemId: "baby"), [], "nothing downloaded yet")

        await sync.refresh()

        XCTAssertEqual(sync.filenames(itemId: "baby"), ["baby_0.svg", "baby_1.svg"])
    }

    func testRefreshInstallsANonArchiveItemAsIndexJSON() async throws {
        // The festivals-manifest shape: the bundle isn't a zip, so the
        // decrypted bytes themselves become the item's index.json.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let payload = Data(#"{"year":2026,"festivals":[]}"#.utf8)
        _ = try stageManifest(at: siteRoot, manifestName: "festivals", itemID: "2026",
                              bundleFilename: "2026.json", plaintext: payload, contentID: "test-app")

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(manifestName: "festivals", contentID: "test-app")

        await sync.refresh()

        XCTAssertEqual(sync.itemStates["2026"], .downloaded)
        struct Year: Decodable, Equatable { let year: Int }
        XCTAssertEqual(sync.loadItemIndex(id: "2026", as: Year.self), Year(year: 2026))
    }

    func testRefreshFailsClosedOnWrongKey() async throws {
        // Encrypted for one app id, but this sync instance belongs to
        // another — the same situation as Colorful's key never opening
        // Prarthana's content.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                              bundleFilename: "a.zip", plaintext: zip, contentID: "encrypted-for-this-app")

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "a-different-app")

        await sync.refresh()

        XCTAssertEqual(sync.itemStates["a"], .failed)
        XCTAssertEqual(sync.syncState, .failed(itemIds: ["a"]))
    }

    func testRefreshFailsClosedOnTamperedBytes() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")

        // Corrupt the published bytes after staging — the checksum in the
        // manifest no longer matches, so this must be caught before decrypt
        // is even attempted.
        let bundlePath = manifestDir.appendingPathComponent("packs/a.zip")
        var bytes = try Data(contentsOf: bundlePath)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: bundlePath)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        await sync.refresh()

        XCTAssertEqual(sync.itemStates["a"], .failed)
    }

    func testRefreshFallsBackToCachedManifestWhenNothingConfigured() async {
        // No SYSHosting.setContentURL, no SYSContentID on the stub bundle —
        // a first launch with nothing cached and nowhere to fetch from.
        SYSHosting.resetForTesting()
        let sync = makeSync(contentID: nil)

        await sync.refresh()

        XCTAssertEqual(sync.syncState, .manifestUnavailable)
    }

    func testPrepareRequiredSucceedsAndFailsInTheSYSContentErrorCurrency() async throws {
        // This is the exact seam SYSBootstrap's `prepareContent` calls — the
        // result has to be a SYSContentError, the same type SYSAssets
        // produces, so `.dataUnavailable`/retry logic works identically
        // regardless of which system is behind it.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                              bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")
        SYSHosting.setContentURL(siteRoot)

        let ok = makeSync(contentID: "test-app")
        let okResult = await ok.prepareRequired()
        guard case .success = okResult else { return XCTFail("expected success") }

        let wrongKey = makeSync(contentID: "a-different-app")
        let failResult = await wrongKey.prepareRequired()
        guard case let .failure(error) = failResult else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .corrupt(pack: "a"))
    }

    func testEnsureCoalescesConcurrentCallsForTheSameItem() async throws {
        // Two taps on the same not-yet-downloaded item must fetch the bytes
        // once, not twice — the same guarantee SYSAssets' fetchOnce gives.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        _ = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                              bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")
        await sync.refresh(downloadAll: false)

        async let first = sync.ensure("a")
        async let second = sync.ensure("a")
        let (firstResult, secondResult) = await (first, second)

        guard case .success = firstResult, case .success = secondResult else {
            return XCTFail("both concurrent calls should succeed")
        }
        XCTAssertEqual(sync.itemStates["a"], .downloaded)
    }

    func testDownloadMissingFetchesEverythingAfterAManifestOnlyRefresh() async throws {
        // The app's shape: index the manifest first (fast, opens the UI),
        // then fetch the packs behind it — with no second manifest request,
        // whatever an ETag would have answered it. More items than the
        // concurrency limit, so the windowing is exercised too.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")
        for id in ["b", "c", "d", "e"] {
            try appendItem(id: id, plaintext: zip, encryptFor: "test-app", to: manifestDir)
        }
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        await sync.refresh(downloadAll: false)
        XCTAssertFalse(sync.hasCachedContent, "a manifest-only refresh downloads nothing")

        var updates: [SYSAssetProgress] = []
        await sync.refresh(progress: { updates.append($0) })

        XCTAssertEqual(sync.syncState, .ready)
        for id in ["a", "b", "c", "d", "e"] {
            XCTAssertEqual(sync.itemStates[id], .downloaded, "\(id) should be on disk")
        }
        XCTAssertEqual(updates.last?.completedPacks, 5)
        XCTAssertEqual(updates.last?.totalPacks, 5)
    }

    func testOverlappingDownloadsOfTheSamePacksDoNotCorruptEachOther() async throws {
        // Launch, a foreground resume and a tap on a tile can all want the
        // same packs at once. Each pack must still install exactly once and
        // nothing may be reported failed.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zip = MiniZipBuilder.build([.init(path: "index.json", contents: Data("{}".utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zip, contentID: "test-app")
        for id in ["b", "c"] {
            try appendItem(id: id, plaintext: zip, encryptFor: "test-app", to: manifestDir)
        }
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")
        await sync.refresh(downloadAll: false)

        async let first: Void = sync.refresh()
        async let second: Void = sync.refresh()
        async let tap = sync.ensure("b")
        _ = await (first, second, tap)

        XCTAssertEqual(sync.syncState, .ready)
        for id in ["a", "b", "c"] {
            XCTAssertEqual(sync.itemStates[id], .downloaded, "\(id) should be on disk")
            XCTAssertNotNil(sync.loadFile(itemId: id, filename: "index.json"))
        }
    }

    func testPrepareRequiredSucceedsWhenSomeItemsFailButOthersAreUsable() async throws {
        // The exact scenario this exists for: one corrupt upload, or one
        // transient failure, must not lock the whole app out when there is
        // still something real to show. Item "a" is encrypted correctly for
        // this sync instance; "b" is encrypted for a different app entirely
        // (standing in for "this one pack is bad" — a checksum mismatch
        // would fail the same way, before decrypt is ever attempted).
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zipA = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"a"}"#.utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zipA, contentID: "test-app")
        let zipB = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"b"}"#.utf8))])
        try appendItem(id: "b", plaintext: zipB, encryptFor: "encrypted-for-someone-else", to: manifestDir)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        let result = await sync.prepareRequired()

        guard case .success = result else { return XCTFail("one bad item must not block the whole app") }
        XCTAssertEqual(sync.itemStates["a"], .downloaded)
        XCTAssertEqual(sync.itemStates["b"], .failed, "the bad item is still recorded as failed, just not blocking")
    }

    func testPrepareRequiredReportsNotConfiguredWhenNothingIsReachableOrCached() async {
        SYSHosting.resetForTesting()
        let sync = makeSync(contentID: nil)

        let result = await sync.prepareRequired()

        guard case let .failure(error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .notConfigured)
    }

    func testEnsureDownloadsOneItemOnDemandWithoutTouchingOthers() async throws {
        // Drawing's shape: `refresh(downloadAll: false)` indexes the
        // manifest but downloads nothing; a category pack is fetched only
        // once someone actually opens it.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let zipA = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"a"}"#.utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zipA, contentID: "test-app")
        let zipB = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"b"}"#.utf8))])
        try appendItem(id: "b", plaintext: zipB, encryptFor: "test-app", to: manifestDir)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        await sync.refresh(downloadAll: false)
        XCTAssertEqual(sync.itemStates["a"], .notDownloaded)
        XCTAssertEqual(sync.itemStates["b"], .notDownloaded)

        let result = await sync.ensure("a")
        guard case .success = result else { return XCTFail("expected success") }

        XCTAssertEqual(sync.itemStates["a"], .downloaded)
        XCTAssertEqual(sync.itemStates["b"], .notDownloaded, "ensure(_:) must not touch items nobody asked for")
    }

    func testManifestDecodesTheAppsOwnFullerType() async throws {
        // `refresh()` only needs manifestVersion + items to drive downloads;
        // an app's own type can carry whatever else it likes (groups, here)
        // and manifest(as:) reads it back from the same fetched file.
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let manifestDir = siteRoot.appendingPathComponent("content", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try """
        {"manifestVersion": 1, "generatedAt": null, "items": [],
         "groups": [{"id": "1", "name": "Worlds", "order": ["a", "b"]}]}
        """.write(to: manifestDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")
        await sync.refresh()

        let full = sync.manifest(as: FullManifestFixture.self)
        XCTAssertEqual(full?.groups, [FullManifestFixture.Group(id: "1", name: "Worlds", order: ["a", "b"])])
    }

    // MARK: - ensureBundle — a companion asset that isn't a manifest item
    // (Prarthana's per-item audio: pointed to by an item's own extra
    // fields, fetched only the first time it's actually played)

    func testEnsureBundleDownloadsDecryptsAndReturnsTheCompanionAsset() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let contentDir = siteRoot.appendingPathComponent("content", isDirectory: true)
        let packsDir = contentDir.appendingPathComponent("packs", isDirectory: true)
        try FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)

        let audioBytes = Data("pretend this is mp3 bytes".utf8)
        let encrypted = try MiniCrypto.encrypt(audioBytes, appStoreID: "test-app")
        try encrypted.write(to: packsDir.appendingPathComponent("hanuman.mp3"))
        let checksum = SYSHash.sha256Hex(encrypted)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        let result = await sync.ensureBundle("packs/hanuman.mp3", checksum: checksum, cacheKey: "hanuman_audio")

        guard case let .success(data) = result else { return XCTFail("expected success") }
        XCTAssertEqual(data, audioBytes)
    }

    func testEnsureBundleServesFromCacheWithoutRefetchingWhenChecksumMatches() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let contentDir = siteRoot.appendingPathComponent("content", isDirectory: true)
        let packsDir = contentDir.appendingPathComponent("packs", isDirectory: true)
        try FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)

        let audioBytes = Data("pretend this is mp3 bytes".utf8)
        let encrypted = try MiniCrypto.encrypt(audioBytes, appStoreID: "test-app")
        let bundlePath = packsDir.appendingPathComponent("hanuman.mp3")
        try encrypted.write(to: bundlePath)
        let checksum = SYSHash.sha256Hex(encrypted)

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        let first = await sync.ensureBundle("packs/hanuman.mp3", checksum: checksum, cacheKey: "hanuman_audio")
        guard case .success = first else { return XCTFail("expected first fetch to succeed") }

        // Remove the remote file entirely — a second call with the same
        // checksum must still succeed, proving it read the local cache
        // rather than trying the network again.
        try FileManager.default.removeItem(at: bundlePath)

        let second = await sync.ensureBundle("packs/hanuman.mp3", checksum: checksum, cacheKey: "hanuman_audio")
        guard case let .success(data) = second else { return XCTFail("expected cached copy to serve without the network") }
        XCTAssertEqual(data, audioBytes)
    }

    func testEnsureBundleFailsClosedOnChecksumMismatch() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }

        let contentDir = siteRoot.appendingPathComponent("content", isDirectory: true)
        let packsDir = contentDir.appendingPathComponent("packs", isDirectory: true)
        try FileManager.default.createDirectory(at: packsDir, withIntermediateDirectories: true)

        let encrypted = try MiniCrypto.encrypt(Data("audio".utf8), appStoreID: "test-app")
        try encrypted.write(to: packsDir.appendingPathComponent("hanuman.mp3"))

        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(contentID: "test-app")

        let result = await sync.ensureBundle(
            "packs/hanuman.mp3",
            checksum: String(repeating: "0", count: 64),
            cacheKey: "hanuman_audio"
        )

        guard case .failure = result else { return XCTFail("expected checksum mismatch to fail closed") }
    }
}

// MARK: - SYSContentSync — what survives a kill, and what the person is told

extension SYSContentSyncRefreshTests {
    private func makeSync(storage: String, keys: String, policy: SYSDownloadPolicy = .onDemand) -> SYSContentSync<FakeContentItem> {
        let sync = SYSContentSync<FakeContentItem>(
            manifestName: "content",
            storageFolder: "sysContentSyncOfflineTests-\(storage)",
            dataVersionKey: SYSSettingsKey<Int>("test.dataVersion.\(keys)", default: 0),
            itemChecksumMapKey: SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(keys)", default: [:]),
            bundle: StubBundle(contentID: "test-app"))
        sync.downloadPolicy = policy
        addTeardownBlock {
            sync.clearAllData()
            try? FileManager.default.removeItem(at: sync.rootURL)
        }
        return sync
    }

    private func stageTwoItems(at siteRoot: URL) throws {
        let zipA = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"a"}"#.utf8))])
        let manifestDir = try stageManifest(at: siteRoot, manifestName: "content", itemID: "a",
                                            bundleFilename: "a.zip", plaintext: zipA, contentID: "test-app")
        let zipB = MiniZipBuilder.build([.init(path: "index.json", contents: Data(#"{"n":"b"}"#.utf8))])
        try appendItem(id: "b", plaintext: zipB, encryptFor: "test-app", to: manifestDir)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    func testAnInterruptedSwapRestoresThePreviousCompleteCopy() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh()
        XCTAssertEqual(first.itemStates["a"], .downloaded)

        let live = first.itemsRoot.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: first.backupRoot, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: live, to: first.backupRoot.appendingPathComponent("a"))
        try FileManager.default.createDirectory(
            at: first.workingRoot.appendingPathComponent("b"), withIntermediateDirectories: true)

        let relaunched = makeSync(storage: id, keys: id)
        relaunched.loadCached(first.items)
        XCTAssertEqual(relaunched.itemStates["a"], .downloaded)
        XCTAssertNotNil(relaunched.loadFile(itemId: "a", filename: "index.json"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: relaunched.workingRoot.path)
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testAnItemStaysAvailableWhenTheCheckSumNeverReachedTheSettings() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh()

        let relaunched = makeSync(storage: id, keys: UUID().uuidString)
        relaunched.loadCached(first.items)
        XCTAssertEqual(relaunched.itemStates["a"], .downloaded)
        XCTAssertEqual(relaunched.itemStates["b"], .downloaded)
    }

    func testAnItemInstalledBeforeReceiptsIsAdoptedFromTheSettingsAndGetsOne() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh()
        let receipt = first.itemsRoot.appendingPathComponent("a/.sys-receipt")
        let checksum = try String(contentsOf: receipt, encoding: .utf8)
        try FileManager.default.removeItem(at: receipt)
        SYSSettings.shared[SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(id)", default: [:])] = ["a": checksum]

        let relaunched = makeSync(storage: id, keys: id)
        relaunched.loadCached(first.items)
        XCTAssertEqual(relaunched.itemStates["a"], .downloaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receipt.path))
    }

    func testANewerVersionOfTheItemIsNotMistakenForTheOneOnTheDevice() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let sync = makeSync(storage: id, keys: id)
        await sync.refresh()

        let newer = sync.items.map { FakeContentItem(id: $0.id, bundle: $0.bundle, checksum: "changed", isPublished: true) }
        sync.loadCached(newer)
        XCTAssertEqual(sync.itemStates["a"], .notDownloaded)
    }

    func testTheFilesListNeverShowsTheReceipt() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString)
        await sync.refresh()
        XCTAssertEqual(sync.filenames(itemId: "a"), ["index.json"])
    }

    func testPrepareRequiredFailsWhenNothingWasDownloadedAndTheServerIsUnreachable() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh(downloadAll: false)

        SYSHosting.setContentURL(tempSiteRoot().appendingPathComponent("gone"))
        let relaunched = makeSync(storage: id, keys: id)
        let result = await relaunched.prepareRequired()
        guard case .failure = result else { return XCTFail("an app with nothing on the device must not open as if ready") }
    }

    func testPrepareRequiredOpensWithWhatIsDownloadedWhenTheServerIsUnreachable() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh(downloadAll: false)
        _ = await first.ensure("a")

        SYSHosting.setContentURL(tempSiteRoot().appendingPathComponent("gone"))
        let relaunched = makeSync(storage: id, keys: id)
        let result = await relaunched.prepareRequired()
        guard case .success = result else { return XCTFail("partial content must still open") }
        XCTAssertEqual(relaunched.itemStates["a"], .downloaded)
        XCTAssertEqual(relaunched.itemStates["b"], .notDownloaded)
    }

    func testAccessSaysWhyAnItemCannotBeOpenedOffline() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString)
        await sync.refresh(downloadAll: false)
        _ = await sync.ensure("a")

        SYSConnectivity.shared.update(isOnline: false)
        addTeardownBlock { await SYSConnectivity.shared.update(isOnline: true) }
        let downloaded = await sync.access("a")
        let missing = await sync.access("b")
        XCTAssertEqual(downloaded, .ready)
        XCTAssertEqual(missing, .needsInternet)

        SYSConnectivity.shared.update(isOnline: true)
        let fetched = await sync.access("b")
        XCTAssertEqual(fetched, .ready)
    }

    func testTheOnDemandPolicyDownloadsNothingByItself() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        SYSConnectivity.shared.update(isOnline: true)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString, policy: .onDemand)
        await sync.refresh(downloadAll: false)
        sync.resumeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sync.itemStates["a"], .notDownloaded)
    }

    func testAPolicyFinishesTheDownloadAfterAManifestOnlyRefresh() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        SYSConnectivity.shared.update(isOnline: true)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString, policy: .anyNetwork)
        await sync.refresh(downloadAll: false)
        await waitUntil { sync.itemStates["a"] == .downloaded && sync.itemStates["b"] == .downloaded }
        XCTAssertEqual(sync.itemStates["a"], .downloaded)
        XCTAssertEqual(sync.itemStates["b"], .downloaded)
    }

    func testResumeFinishesWhatWasLeftWhenTheConnectionReturns() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        SYSConnectivity.shared.update(isOnline: true)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        await first.refresh(downloadAll: false)
        _ = await first.ensure("a")

        let relaunched = makeSync(storage: id, keys: id, policy: .anyNetwork)
        relaunched.loadCached(first.items)
        XCTAssertEqual(relaunched.itemStates["b"], .notDownloaded)
        relaunched.resumeIfNeeded()
        await waitUntil { relaunched.itemStates["b"] == .downloaded }
        XCTAssertEqual(relaunched.itemStates["b"], .downloaded)
    }
}

extension SYSContentSyncRefreshTests {
    private func stageAudio(_ text: String, at siteRoot: URL, name: String = "hanuman.mp3") throws -> (checksum: String, bytes: Data) {
        let packs = siteRoot.appendingPathComponent("content/packs", isDirectory: true)
        try FileManager.default.createDirectory(at: packs, withIntermediateDirectories: true)
        let bytes = Data(text.utf8)
        let encrypted = try MiniCrypto.encrypt(bytes, appStoreID: "test-app")
        try encrypted.write(to: packs.appendingPathComponent(name))
        return (SYSHash.sha256Hex(encrypted), bytes)
    }

    func testAKeptAudioFileIsStillCurrentAfterARelaunchWithoutAnySettings() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        let audio = try stageAudio("version one", at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let first = makeSync(storage: id, keys: id)
        _ = await first.ensureBundle("packs/hanuman.mp3", checksum: audio.checksum, cacheKey: "hanuman_audio")

        let relaunched = makeSync(storage: id, keys: UUID().uuidString)
        XCTAssertTrue(relaunched.isBundleKept(checksum: audio.checksum, cacheKey: "hanuman_audio"))
        XCTAssertFalse(relaunched.isBundleKept(checksum: "another", cacheKey: "hanuman_audio"))
    }

    func testANewVersionOfAnAudioFileReplacesTheOldOne() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        let one = try stageAudio("version one", at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let sync = makeSync(storage: id, keys: id)
        _ = await sync.ensureBundle("packs/hanuman.mp3", checksum: one.checksum, cacheKey: "hanuman_audio")
        let two = try stageAudio("version two", at: siteRoot)
        let result = await sync.ensureBundle("packs/hanuman.mp3", checksum: two.checksum, cacheKey: "hanuman_audio")
        guard case let .success(data) = result else { return XCTFail("expected the new version") }
        XCTAssertEqual(data, two.bytes)
        let files = try FileManager.default.contentsOfDirectory(atPath: sync.bundlesRoot.path)
        XCTAssertEqual(files.count, 1)
    }

    func testTheCopyOnTheDevicePlaysWhenANewerOneCannotBeFetched() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        let one = try stageAudio("version one", at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let sync = makeSync(storage: id, keys: id)
        _ = await sync.ensureBundle("packs/hanuman.mp3", checksum: one.checksum, cacheKey: "hanuman_audio")

        SYSHosting.setContentURL(tempSiteRoot().appendingPathComponent("gone"))
        let result = await sync.ensureBundle("packs/hanuman.mp3", checksum: "a-newer-checksum", cacheKey: "hanuman_audio")
        guard case let .success(data) = result else { return XCTFail("the held copy must still play") }
        XCTAssertEqual(data, one.bytes)
    }

    func testAnAudioFileKeptBeforeThisVersionIsAdoptedFromTheSettings() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        let audio = try stageAudio("legacy", at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let id = UUID().uuidString
        let sync = makeSync(storage: id, keys: id)
        try FileManager.default.createDirectory(at: sync.bundlesRoot, withIntermediateDirectories: true)
        try audio.bytes.write(to: sync.bundlesRoot.appendingPathComponent("hanuman_audio"))
        SYSSettings.shared[SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(id)", default: [:])] = ["hanuman_audio": audio.checksum]

        XCTAssertTrue(sync.isBundleKept(checksum: audio.checksum, cacheKey: "hanuman_audio"))
        let files = try FileManager.default.contentsOfDirectory(atPath: sync.bundlesRoot.path)
        XCTAssertFalse(files.contains("hanuman_audio"))
    }

    func testTheRefreshHookRunsWhoeverStartedTheRefresh() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString)
        var calls = 0
        sync.didRefresh = { calls += 1 }
        await sync.refresh(downloadAll: false)
        XCTAssertEqual(calls, 1)
    }

    func testComingBackAfterTheIntervalRefreshesAgain() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        SYSConnectivity.shared.update(isOnline: true)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString, policy: .anyNetwork)
        var calls = 0
        sync.didRefresh = { calls += 1 }
        sync.refreshInterval = 0
        await sync.refresh()
        let afterLaunch = calls
        try await Task.sleep(nanoseconds: 20_000_000)
        sync.resumeIfNeeded()
        await waitUntil { calls > afterLaunch }
        XCTAssertGreaterThan(calls, afterLaunch)
    }

    func testComingBackWithinTheIntervalDoesNotRefresh() async throws {
        let siteRoot = tempSiteRoot()
        defer { try? FileManager.default.removeItem(at: siteRoot) }
        try stageTwoItems(at: siteRoot)
        SYSHosting.setContentURL(siteRoot)
        SYSConnectivity.shared.update(isOnline: true)
        let sync = makeSync(storage: UUID().uuidString, keys: UUID().uuidString, policy: .anyNetwork)
        var calls = 0
        sync.didRefresh = { calls += 1 }
        await sync.refresh()
        let afterLaunch = calls
        sync.resumeIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(calls, afterLaunch)
    }
}

private struct FullManifestFixture: Decodable {
    struct Group: Decodable, Equatable { let id: String; let name: String; let order: [String] }
    let manifestVersion: Int
    let groups: [Group]
}

#endif
