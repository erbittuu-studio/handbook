import XCTest
@testable import SYSKit

// MARK: - Settings

final class SYSSettingsTests: XCTestCase {
    private var settings: SYSSettings!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SYSKitTests-\(UUID().uuidString)")
        settings = SYSSettings(defaults: defaults)
    }

    func testDefaultIsUsedWhenUnset() {
        XCTAssertEqual(settings[SYSSettingsKey<Int>("missing", default: 42)], 42)
        XCTAssertFalse(settings[SYSSettingsKey<Bool>("missing", default: false)])
    }

    /// `false` must be distinguishable from "never set" — the classic
    /// UserDefaults trap.
    func testStoredFalseIsNotTreatedAsMissing() {
        let key = SYSSettingsKey<Bool>("flag", default: true)
        settings[key] = false
        XCTAssertFalse(settings[key])
    }

    func testRoundTrips() {
        let text = SYSSettingsKey<String>("name", default: "")
        settings[text] = "colorful"
        XCTAssertEqual(settings[text], "colorful")
    }

    func testRemove() {
        let key = SYSSettingsKey<Int>("count", default: 0)
        settings[key] = 5
        XCTAssertTrue(settings.contains(key))
        settings.remove(key)
        XCTAssertFalse(settings.contains(key))
        XCTAssertEqual(settings[key], 0)
    }

    /// Native arrays/dictionaries round-trip as plain plist values, not JSON —
    /// proven by reading the same key back with `defaults.array`/`.dictionary`
    /// directly, the way an app that wrote one before adopting SYSSettings did.
    func testNativeArrayIsAPlainPlistArray() {
        let key = SYSSettingsKey<[Int]>("ids", default: [])
        settings[key] = [1, 2, 3]
        XCTAssertEqual(defaults.array(forKey: "ids") as? [Int], [1, 2, 3])
        XCTAssertEqual(settings[key], [1, 2, 3])
    }

    func testNativeDictionaryIsAPlainPlistDictionary() {
        let key = SYSSettingsKey<[String: String]>("checksums", default: [:])
        settings[key] = ["a": "1"]
        XCTAssertEqual(defaults.dictionary(forKey: "checksums") as? [String: String], ["a": "1"])
        XCTAssertEqual(settings[key], ["a": "1"])
    }

    func testMissingNativeCollectionUsesDefault() {
        XCTAssertEqual(settings[SYSSettingsKey<[String]>("missing", default: ["x"])], ["x"])
        XCTAssertEqual(settings[SYSSettingsKey<[String: Int]>("missing2", default: ["y": 1])], ["y": 1])
    }
}

// MARK: - SYSHash

final class SYSHashTests: XCTestCase {
    // FIPS 180-4 vectors. The fallback is only compiled on non-Apple platforms,
    // so it is tested directly rather than through sha256Hex — otherwise CI on
    // macOS would verify CryptoKit and never touch the code that actually ships
    // to a Linux build.
    func testKnownVectors() {
        let cases: [(String, String)] = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
             "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        ]
        for (input, expected) in cases {
            let data = Data(input.utf8)
            XCTAssertEqual(SYSHash.sha256Hex(data), expected, "sha256Hex(\(input.prefix(12)))")
            XCTAssertEqual(SYSHash.fallbackSHA256Hex(data), expected, "fallback(\(input.prefix(12)))")
        }
    }

    func testFallbackMatchesPlatformImplementation() {
        // Multi-block input, to exercise the chunk loop rather than one padded block.
        let data = Data((0 ..< 5000).map { UInt8($0 % 251) })
        XCTAssertEqual(SYSHash.sha256Hex(data), SYSHash.fallbackSHA256Hex(data))
    }

    func testLengthPaddingBoundaries() {
        // 55/56/57 and 63/64/65 bytes straddle the padding block boundary, where
        // a wrong implementation still passes short inputs.
        for length in [55, 56, 57, 63, 64, 65, 119, 120] {
            let data = Data(repeating: 0x61, count: length)
            XCTAssertEqual(SYSHash.sha256Hex(data), SYSHash.fallbackSHA256Hex(data), "length \(length)")
        }
    }
}

// MARK: - SYSStored

private let storedSuite = UserDefaults(suiteName: "sysstored.tests")!

private final class TestPrefs: ObservableObject {
    @SYSStored("music", default: true, defaults: storedSuite) var music: Bool
    @SYSStored("count", default: 3, defaults: storedSuite) var count: Int
    @SYSStored("name", default: "unset", defaults: storedSuite) var name: String
}

final class SYSStoredTests: XCTestCase {
    private var prefs: TestPrefs!

    override func setUp() {
        super.setUp()
        for key in ["music", "count", "name"] { storedSuite.removeObject(forKey: key) }
        prefs = TestPrefs()
    }

    func testDefaultAppliesWhenTheKeyIsAbsent() {
        XCTAssertTrue(prefs.music)
        XCTAssertEqual(prefs.count, 3)
        XCTAssertEqual(prefs.name, "unset")
    }

    func testStoredFalseIsAValueNotAMissingKey() {
        // The bug defaults.bool(forKey:) invites: false and "absent" are the same
        // there, so a user who switched something off gets it switched back on.
        prefs.music = false
        XCTAssertFalse(prefs.music)
    }

    func testWritesPersistToTheUnderlyingDefaults() {
        prefs.count = 11
        XCTAssertEqual(storedSuite.object(forKey: "count") as? Int, 11)
    }

    func testReadsAValueWrittenNativelyByAnOlderBuild() {
        // Preferences inherited from the Objective-C app are plain plist values.
        // Encoding them any other way would read as "no value" on every existing
        // install and silently reset everyone's settings on upgrade.
        storedSuite.set(false, forKey: "music")
        storedSuite.set("Utsav", forKey: "name")
        XCTAssertFalse(prefs.music)
        XCTAssertEqual(prefs.name, "Utsav")
    }

    func testTwoInstancesSeeTheSameStoredValue() {
        prefs.count = 7
        XCTAssertEqual(TestPrefs().count, 7)
    }
}
