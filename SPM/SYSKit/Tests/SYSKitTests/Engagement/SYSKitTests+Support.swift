import XCTest
@testable import SYSKit

// MARK: - Test support

/// A `FileManager` rooted in a fresh temporary directory.
///
/// `SYSContent` resolves Application Support, which under `swift test` on macOS
/// is the developer's real `~/Library/Application Support`. Tests built a
/// `SYSAssets` with the default manager and asserted on what they found there,
/// so running the suite wrote into the home directory and the next run read it
/// back: they passed on a clean machine and failed on the second run, which is
/// the worst way for a test to be wrong.
///
/// Both spellings of the lookup are overridden. `SYSContent` uses the throwing
/// single-URL one, and overriding only `urls(for:in:)` looks right, changes
/// nothing, and leaves the tests still reading the real directory.
///
/// Each instance gets its own directory, so tests cannot see one another's
/// leftovers either.
final class TemporaryFileManager: FileManager {
    private let root: URL

    override init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SYSKitTests-\(UUID().uuidString)", isDirectory: true)
        super.init()
        try? createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func url(for directory: FileManager.SearchPathDirectory,
                      in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?,
                      create shouldCreate: Bool) throws -> URL {
        root
    }

    override func urls(for directory: FileManager.SearchPathDirectory,
                       in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        [root]
    }
}

// MARK: - Helpers

/// Bundle stub so version-dependent logic is testable without a host app.
///
/// Not `private`: SYSUpdateTests, in SYSKitTests+Core.swift, uses this — moved
/// here when the one file this all used to live in got split by area, and
/// `private` is file-scoped, so it has to be at least `internal` to still be
/// visible from there.
final class StubBundle: Bundle, @unchecked Sendable {
    private let version: String
    private let contentID: String?
    init(version: String = "1.0", contentID: String? = nil) {
        self.version = version
        self.contentID = contentID
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func object(forInfoDictionaryKey key: String) -> Any? {
        switch key {
        case "CFBundleShortVersionString": return version
        case "SYSContentID": return contentID
        default: return nil
        }
    }
}
