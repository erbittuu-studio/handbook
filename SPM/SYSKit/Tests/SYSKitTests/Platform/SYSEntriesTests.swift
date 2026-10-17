import XCTest
@testable import SYSKit

@MainActor
final class SYSEntriesTests: XCTestCase {
    private func delivered(by entries: SYSEntries) -> [SYSEntry] {
        var received: [SYSEntry] = []
        entries.markReady { received.append($0) }
        return received
    }

    func testALinkBecomesAKindAndAnID() throws {
        let entries = SYSEntries()
        XCTAssertTrue(entries.open(try XCTUnwrap(URL(string: "demo://Pack/7")), scheme: "demo"))
        XCTAssertEqual(delivered(by: entries), [SYSEntry(kind: "pack", id: "7")])
    }

    func testALinkWithoutAnIDKeepsOnlyItsKind() throws {
        let entries = SYSEntries()
        entries.open(try XCTUnwrap(URL(string: "demo://calendar")), scheme: "demo")
        XCTAssertEqual(delivered(by: entries), [SYSEntry(kind: "calendar", id: nil)])
    }

    func testAnotherAppsLinkIsIgnored() throws {
        let entries = SYSEntries()
        XCTAssertFalse(entries.open(try XCTUnwrap(URL(string: "other://pack/7")), scheme: "demo"))
        XCTAssertEqual(delivered(by: entries), [])
    }

    func testAnEntryWaitsUntilTheAppIsReadyAndThenArrivesAtOnce() {
        let entries = SYSEntries()
        entries.receive(.action("quiz"))
        var received: [SYSEntry] = []
        entries.markReady { received.append($0) }
        XCTAssertEqual(received, [.action("quiz")])
        entries.receive(SYSEntry(kind: "pack", id: "2"))
        XCTAssertEqual(received.last, SYSEntry(kind: "pack", id: "2"))
    }

    func testAShortcutNamesItselfAfterTheBundle() {
        XCTAssertTrue(SYSEntries().shortcutPrefix.hasSuffix(".quickaction."))
    }

    #if canImport(CoreSpotlight) && !os(watchOS)
    func testASearchResultBecomesAKindAndAnID() {
        let entries = SYSEntries()
        entries.openSpotlight("category-space")
        XCTAssertEqual(delivered(by: entries), [SYSEntry(kind: "category", id: "space")])
    }

    func testASearchResultKeepsDashesInItsID() {
        let entries = SYSEntries()
        entries.openSpotlight("reader-hanuman-chalisa")
        XCTAssertEqual(delivered(by: entries), [SYSEntry(kind: "reader", id: "hanuman-chalisa")])
    }
    #endif
}

final class SYSConfigSearchTests: XCTestCase {
    func testTheSearchSectionDecodesAndItsAbsenceIsFine() throws {
        let with = try JSONDecoder().decode(
            SYSConfigData.self, from: Data(#"{"search":{"keywords":["abc","alphabet"]}}"#.utf8)
        )
        XCTAssertEqual(with.search?.keywords, ["abc", "alphabet"])
        let without = try JSONDecoder().decode(SYSConfigData.self, from: Data("{}".utf8))
        XCTAssertNil(without.search)
    }
}
