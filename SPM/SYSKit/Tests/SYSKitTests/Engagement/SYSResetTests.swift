import XCTest
@testable import SYSKit

final class SYSResetTests: XCTestCase {
    func testRemovingContentsEmptiesAFolderButKeepsTheFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SYSResetTests-\(UUID().uuidString)")
        let nested = folder.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nested.appendingPathComponent("file.txt"))
        try Data("y".utf8).write(to: folder.appendingPathComponent("top.txt"))

        SYSReset.removeContents(of: folder)

        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(left.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        try FileManager.default.removeItem(at: folder)
    }

    func testRemovingContentsOfAMissingFolderDoesNothing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("SYSResetTests-missing-\(UUID().uuidString)")
        SYSReset.removeContents(of: missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testRemovingContentsKeepsTheNamedFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SYSResetTests-keep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Preferences"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Caches"), withIntermediateDirectories: true)

        SYSReset.removeContents(of: folder, keeping: ["Preferences"])

        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(left, ["Preferences"])
        try FileManager.default.removeItem(at: folder)
    }
}

@MainActor
final class SYSResetRegistryTests: XCTestCase {
    private final class Probe: SYSResettable {
        var resets = 0
        func resetForFreshInstall() { resets += 1 }
    }

    func testEveryRegisteredObjectIsResetOnce() {
        let first = Probe()
        let second = Probe()
        SYSResetRegistry.register(first)
        SYSResetRegistry.register(second)

        SYSResetRegistry.resetAll()

        XCTAssertEqual(first.resets, 1)
        XCTAssertEqual(second.resets, 1)
    }

    func testAnObjectThatIsGoneIsSkipped() {
        var gone: Probe? = Probe()
        SYSResetRegistry.register(gone!)
        gone = nil
        let kept = Probe()
        SYSResetRegistry.register(kept)

        SYSResetRegistry.resetAll()

        XCTAssertEqual(kept.resets, 1)
    }
}
