import XCTest
@testable import SYSKit

// MARK: - Locale matching

final class SYSLocaleTests: XCTestCase {
    private let worlds = [
        "en": "Weather", "es": "Tiempo", "pt-BR": "Tempo",
        "zh-Hans": "天气", "zh-Hant": "天氣"
    ]

    /// The reason this type exists. The old lookup was
    /// `values[String(locale.prefix(2))]`, which asks for "zh" and therefore
    /// cannot tell Simplified from Traditional — one script silently served the
    /// other, or both fell through to English.
    func testSimplifiedAndTraditionalChineseAreNotConfused() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["zh-Hans-CN"]), "天气")
        XCTAssertEqual(SYSLocale.match(worlds, for: ["zh-Hant-TW"]), "天氣")
        XCTAssertEqual(SYSLocale.match(worlds, for: ["zh-Hant-HK"]), "天氣")
    }

    /// The other half of the same bug: a device says "pt-BR", the old lookup
    /// asked for "pt", and a "pt-BR" key was unreachable.
    func testRegionalTagMatchesRegionalKey() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["pt-BR"]), "Tempo")
    }

    /// Narrowing: a key may be broader than the tag asked for.
    func testRegionalTagFallsBackToBareLanguage() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["es-MX"]), "Tiempo")
        XCTAssertEqual(SYSLocale.match(worlds, for: ["en-GB"]), "Weather")
    }

    /// Widening: a key may be narrower than the tag asked for. A device set to
    /// plain "pt" should take Brazilian Portuguese over English.
    func testBareLanguageTakesARegionalKeyOverEnglish() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["pt"]), "Tempo")
    }

    /// Each preferred language is exhausted before the next is tried.
    func testFirstPreferredLanguageWins() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["es-ES", "en-US"]), "Tiempo")
        XCTAssertEqual(SYSLocale.match(worlds, for: ["ko-KR", "es-ES"]), "Tiempo")
    }

    func testFallsBackToEnglishThenToAnything() {
        XCTAssertEqual(SYSLocale.match(worlds, for: ["ko-KR"]), "Weather")
        XCTAssertEqual(SYSLocale.match(["ja": "天気"], for: ["ko-KR"]), "天気")
        XCTAssertNil(SYSLocale.match([String: String](), for: ["en"]))
    }

    /// `zh_Hant` and `ZH-HANT` are the same request as `zh-Hant`.
    func testTagsAreCaseAndSeparatorInsensitive() {
        XCTAssertEqual(SYSLocale.match(["zh-Hant": "天氣"], for: ["zh_Hant_TW"]), "天氣")
        XCTAssertEqual(SYSLocale.match(["ZH-HANT": "天氣"], for: ["zh-Hant"]), "天氣")
    }

    /// The same matcher backs config text, so a bare string still reads as en.
    func testLocalizedTextDecodesBareStringAndResolves() throws {
        let bare = try JSONDecoder().decode(SYSLocalizedText.self, from: Data(#""Baby""#.utf8))
        XCTAssertEqual(bare.resolved(for: ["ar-SA"]), "Baby")

        let keyed = try JSONDecoder().decode(
            SYSLocalizedText.self,
            from: Data(#"{"en":"Baby","ar":"الرضّع"}"#.utf8)
        )
        XCTAssertEqual(keyed.resolved(for: ["ar-SA"]), "الرضّع")
        XCTAssertEqual(keyed.resolved(for: ["de-DE"]), "Baby")
    }
}

// MARK: - SYSPendingIntent

final class SYSPendingIntentTests: XCTestCase {
    @MainActor
    func testDeliversImmediatelyOnceReady() {
        let pending = SYSPendingIntent<Int>()
        var delivered: Int?
        pending.markReady { delivered = $0 }
        pending.receive(1)
        XCTAssertEqual(delivered, 1)
    }

    @MainActor
    func testQueuesUntilReady() {
        let pending = SYSPendingIntent<Int>()
        pending.receive(1)
        var delivered: Int?
        pending.markReady { delivered = $0 }
        XCTAssertEqual(delivered, 1)
    }

    /// A second intent arriving before delivery replaces the first — the
    /// user acted again while still loading, and wants that one.
    @MainActor
    func testSecondQueuedIntentReplacesTheFirst() {
        let pending = SYSPendingIntent<Int>()
        pending.receive(1)
        pending.receive(2)
        var delivered: Int?
        pending.markReady { delivered = $0 }
        XCTAssertEqual(delivered, 2)
    }

    @MainActor
    func testResetStopsFurtherDelivery() {
        let pending = SYSPendingIntent<Int>()
        var delivered: Int?
        pending.markReady { delivered = $0 }
        pending.reset()
        pending.receive(1)
        XCTAssertNil(delivered)
    }
}

// MARK: - SYSDeepLink

final class SYSDeepLinkTests: XCTestCase {
    func testMatchesOwnSchemeOnly() {
        let url = URL(string: "colorful://category/5")!
        XCTAssertTrue(SYSDeepLink.matches(url, scheme: "colorful"))
        XCTAssertFalse(SYSDeepLink.matches(url, scheme: "prarthana"))
    }

    func testComponentsNilOnSchemeMismatch() {
        let url = URL(string: "https://example.com")!
        XCTAssertNil(SYSDeepLink.components(url, expectingScheme: "colorful"))
    }

    func testComponentsParsesHostAndPath() {
        let url = URL(string: "kidslearning://pack/42")!
        let components = SYSDeepLink.components(url, expectingScheme: "kidslearning")
        XCTAssertEqual(components?.host, "pack")
        XCTAssertEqual(components?.path, "/42")
    }
}

// MARK: - SYSPublishing

private struct DraftItem: SYSPublishable, Equatable {
    let id: String
    let isPublished: Bool
}

final class SYSPublishingTests: XCTestCase {
    private let items = [
        DraftItem(id: "live", isPublished: true),
        DraftItem(id: "draft", isPublished: false)
    ]

    func testIncludingUnpublishedReturnsEverything() {
        XCTAssertEqual(SYSPublishing.visible(items, includeUnpublished: true), items)
    }

    func testExcludingUnpublishedFiltersDrafts() {
        XCTAssertEqual(SYSPublishing.visible(items, includeUnpublished: false), [items[0]])
    }
}

// MARK: - SYSZip

/// Hand-assembles a minimal, valid ZIP (stored entries only — no encoder for
/// deflate here) so the reader's byte-format handling is testable without
/// shelling out to `zip`, which is what actually keeps this portable to the
/// Linux CI runner `SYSZip.unzip` itself can't run on (no `Compression`
/// framework there — this suite runs on macOS, where it can).
private enum MiniZipBuilder {
    struct Entry {
        let path: String
        let contents: Data
    }

    static func build(_ entries: [Entry]) -> Data {
        var body = Data()
        var central = Data()

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let offset = UInt32(body.count)

            var local = Data()
            local.appendLE(UInt32(0x04034b50))
            local.appendLE(UInt16(20))               // version needed
            local.appendLE(UInt16(0))                // flags
            local.appendLE(UInt16(0))                // method: stored
            local.appendLE(UInt16(0))                // mod time
            local.appendLE(UInt16(0))                // mod date
            local.appendLE(UInt32(0))                // crc32 (unused by SYSZip)
            local.appendLE(UInt32(entry.contents.count))
            local.appendLE(UInt32(entry.contents.count))
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0))                // extra length
            local.append(nameData)
            local.append(entry.contents)
            body.append(local)

            var centralEntry = Data()
            centralEntry.appendLE(UInt32(0x02014b50))
            centralEntry.appendLE(UInt16(20))         // version made by
            centralEntry.appendLE(UInt16(20))         // version needed
            centralEntry.appendLE(UInt16(0))          // flags
            centralEntry.appendLE(UInt16(0))          // method
            centralEntry.appendLE(UInt16(0))          // mod time
            centralEntry.appendLE(UInt16(0))          // mod date
            centralEntry.appendLE(UInt32(0))          // crc32
            centralEntry.appendLE(UInt32(entry.contents.count))
            centralEntry.appendLE(UInt32(entry.contents.count))
            centralEntry.appendLE(UInt16(nameData.count))
            centralEntry.appendLE(UInt16(0))          // extra length
            centralEntry.appendLE(UInt16(0))          // comment length
            centralEntry.appendLE(UInt16(0))          // disk number start
            centralEntry.appendLE(UInt16(0))          // internal attrs
            centralEntry.appendLE(UInt32(0))          // external attrs
            centralEntry.appendLE(offset)
            centralEntry.append(nameData)
            central.append(centralEntry)
        }

        var archive = body
        let centralOffset = UInt32(archive.count)
        archive.append(central)

        var eocd = Data()
        eocd.appendLE(UInt32(0x06054b50))
        eocd.appendLE(UInt16(0))                      // disk number
        eocd.appendLE(UInt16(0))                      // disk with CD
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(central.count))
        eocd.appendLE(centralOffset)
        eocd.appendLE(UInt16(0))                      // comment length
        archive.append(eocd)

        return archive
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

final class SYSZipTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testExtractsFlatAndNestedStoredEntries() throws {
        let archiveData = MiniZipBuilder.build([
            .init(path: "a.txt", contents: Data("hello".utf8)),
            .init(path: "sub/b.txt", contents: Data("nested".utf8))
        ])
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let zipURL = workDir.appendingPathComponent("test.zip")
        try archiveData.write(to: zipURL)
        let destination = workDir.appendingPathComponent("out")

        try SYSZip.unzip(at: zipURL, to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("a.txt"), encoding: .utf8),
            "hello")
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("sub/b.txt"), encoding: .utf8),
            "nested")
    }

    /// The shape every content bundle this session found actually ships in:
    /// every entry wrapped under one top-level folder named after the item
    /// — `achyutam_keshavam/index.json`, not `index.json`. Caught live
    /// against a real staged bundle before this stripping existed.
    func testStripsASingleCommonTopLevelFolder() throws {
        let archiveData = MiniZipBuilder.build([
            .init(path: "item/index.json", contents: Data("{}".utf8)),
            .init(path: "item/item_en.json", contents: Data("en".utf8))
        ])
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let zipURL = workDir.appendingPathComponent("test.zip")
        try archiveData.write(to: zipURL)
        let destination = workDir.appendingPathComponent("out")

        try SYSZip.unzip(at: zipURL, to: destination)

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("index.json"), encoding: .utf8),
            "{}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("item").path))
    }

    func testNonZipDataThrows() throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let notZipURL = workDir.appendingPathComponent("not-a-zip")
        try Data("plain text, not a zip".utf8).write(to: notZipURL)

        XCTAssertThrowsError(try SYSZip.unzip(at: notZipURL, to: workDir.appendingPathComponent("out")))
    }
}

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
    private func makeSync() -> SYSContentSync<FakeContentItem> {
        let suffix = UUID().uuidString
        let dataVersionKey = SYSSettingsKey<Int>("test.dataVersion.\(suffix)", default: 0)
        let itemChecksumMapKey = SYSSettingsKey<[String: String]>("test.itemChecksumMap.\(suffix)", default: [:])
        let sync = SYSContentSync<FakeContentItem>(
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

    func testLoadBundledMarksEverythingDownloaded() {
        let sync = makeSync()
        let items = [
            FakeContentItem(id: "a", bundle: "a.zip", checksum: nil, isPublished: true),
            FakeContentItem(id: "b", bundle: "b.zip", checksum: nil, isPublished: true)
        ]

        sync.loadBundled(items)

        XCTAssertTrue(sync.hasCachedContent)
        XCTAssertTrue(sync.isAvailable(id: "a"))
        XCTAssertTrue(sync.isAvailable(id: "b"))
        XCTAssertEqual(sync.syncState, .ready)
        XCTAssertEqual(sync.meta(for: "a"), items[0])
    }

    func testClearAllDataResetsStateAndVersion() {
        let sync = makeSync()
        sync.loadBundled([FakeContentItem(id: "a", bundle: "a.zip", checksum: nil, isPublished: true)])
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
}
