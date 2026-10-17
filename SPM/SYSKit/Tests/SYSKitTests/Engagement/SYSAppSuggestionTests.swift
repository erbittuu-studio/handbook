import XCTest
@testable import SYSKit

final class SYSAppSuggestionPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func app(_ id: String, category: String? = nil) -> SYSAppCatalogEntry {
        SYSAppCatalogEntry(id: id, name: "App \(id)", category: category)
    }

    private func due(opens: Int, nextOpen: Int = 5, lastShown: Date? = nil, remindAfter: Date? = nil) -> Bool {
        SYSAppSuggestionPolicy.isDue(opens: opens, nextOpen: nextOpen, lastShown: lastShown, remindAfter: remindAfter, now: now)
    }

    func testTheFirstPopupIsOnTheFifthOpen() {
        XCTAssertFalse(due(opens: 4))
        XCTAssertTrue(due(opens: 5))
    }

    func testTheSequenceIsFifthEighthTwelfthSeventeenthTwentyThirdThirtiethThenEveryTenth() {
        var opens = SYSAppSuggestionPolicy.firstOpen
        var seen = [opens]
        for shown in 1...8 {
            opens = SYSAppSuggestionPolicy.nextOpen(after: opens, shownCount: shown)
            seen.append(opens)
        }
        XCTAssertEqual(seen, [5, 8, 12, 17, 23, 30, 40, 50, 60])
    }

    func testASlotAnotherPromptTookIsNotLost() {
        XCTAssertTrue(due(opens: 6))
        XCTAssertEqual(SYSAppSuggestionPolicy.nextOpen(after: 6, shownCount: 1), 9)
    }

    func testAtLeastADayPassesBetweenPopups() {
        XCTAssertFalse(due(opens: 8, nextOpen: 8, lastShown: now.addingTimeInterval(-3_600)))
        XCTAssertTrue(due(opens: 8, nextOpen: 8, lastShown: now.addingTimeInterval(-86_401)))
    }

    func testRemindMeLaterComesBackOnItsDayAndNotBefore() {
        XCTAssertFalse(due(opens: 99, nextOpen: 5, remindAfter: now.addingTimeInterval(3_600)))
        XCTAssertTrue(due(opens: 1, nextOpen: 5, remindAfter: now.addingTimeInterval(-1)))
    }

    func testNothingIsShownRightAfterAReviewRequest() {
        XCTAssertTrue(SYSAppSuggestionPolicy.reviewMayBeOpen(lastRequest: now.addingTimeInterval(-30), now: now))
        XCTAssertFalse(SYSAppSuggestionPolicy.reviewMayBeOpen(lastRequest: now.addingTimeInterval(-120), now: now))
        XCTAssertFalse(SYSAppSuggestionPolicy.reviewMayBeOpen(lastRequest: nil, now: now))
    }

    func testTheRecommendationListDecidesTheOrder() {
        let apps = [app("1"), app("2"), app("3")]
        let first = SYSAppSuggestionPolicy.next(from: apps, seen: [], opened: [], recommends: ["3", "1"])
        XCTAssertEqual(first?.app.id, "3")
        let second = SYSAppSuggestionPolicy.next(from: apps, seen: first?.seen ?? [], opened: [], recommends: ["3", "1"])
        XCTAssertEqual(second?.app.id, "1")
        let third = SYSAppSuggestionPolicy.next(from: apps, seen: second?.seen ?? [], opened: [], recommends: ["3", "1"])
        XCTAssertEqual(third?.app.id, "2")
    }

    func testWithoutAListTheSameCategoryComesFirst() {
        let apps = [app("1", category: "creativity"), app("2", category: "kids"), app("3", category: "lifestyle")]
        XCTAssertEqual(SYSAppSuggestionPolicy.next(from: apps, seen: [], opened: [], category: "kids")?.app.id, "2")
        XCTAssertEqual(SYSAppSuggestionPolicy.next(from: apps, seen: [], opened: [], category: nil)?.app.id, "1")
    }

    func testAnOpenedAppIsNeverSuggestedAgain() {
        let apps = [app("1"), app("2"), app("3")]
        XCTAssertEqual(SYSAppSuggestionPolicy.next(from: apps, seen: [], opened: ["1", "2"])?.app.id, "3")
        XCTAssertNil(SYSAppSuggestionPolicy.next(from: [app("1")], seen: [], opened: ["1"]))
    }

    func testEveryAppIsShownBeforeOneComesRoundAgain() {
        let apps = [app("1"), app("2")]
        let next = SYSAppSuggestionPolicy.next(from: apps, seen: ["1", "2"], opened: [])
        XCTAssertEqual(next?.app.id, "1")
        XCTAssertEqual(next?.seen, ["1"])
    }

    func testAnotherAppNeedsAtLeastTwoUnopened() {
        let apps = [app("1"), app("2")]
        XCTAssertTrue(SYSAppSuggestionPolicy.hasAnother(apps: apps, opened: []))
        XCTAssertFalse(SYSAppSuggestionPolicy.hasAnother(apps: apps, opened: ["2"]))
    }
}

final class SYSAppCatalogEntryTextTests: XCTestCase {
    private let entry = SYSAppCatalogEntry(
        id: "1",
        name: "Colorful: Kids Coloring Book",
        tagline: "",
        blurb: ["en": "Colouring fun", "hi": "रंग भरने का मज़ा"],
        highlights: ["en": ["Free"], "hi": ["मुफ़्त"]]
    )

    func testTheShortNameIsTheTitleBeforeTheColon() {
        XCTAssertEqual(entry.shortName, "Colorful")
        XCTAssertEqual(SYSAppCatalogEntry(id: "2", name: "Prarthana").shortName, "Prarthana")
    }

    func testBlurbAndHighlightsFollowTheLanguage() {
        XCTAssertEqual(entry.blurb(for: ["hi"]), "रंग भरने का मज़ा")
        XCTAssertEqual(entry.highlights(for: ["hi-IN"]), ["मुफ़्त"])
        XCTAssertEqual(entry.blurb(for: ["fr"]), "Colouring fun")
    }

    func testAnEmptyTaglineIsNotShown() {
        let bare = SYSAppCatalogEntry(id: "3", name: "Plain", tagline: "")
        XCTAssertNil(bare.blurb(for: ["en"]))
        XCTAssertTrue(bare.highlights(for: ["en"]).isEmpty)
    }

    func testTheSuggestionTextHasHindiAndGujarati() {
        XCTAssertEqual(SYSAppSuggestionText.forLanguages(["hi"]).download, "डाउनलोड करें")
        XCTAssertEqual(SYSAppSuggestionText.forLanguages(["gu"]).later, "પછી યાદ અપાવો")
        XCTAssertEqual(SYSAppSuggestionText.forLanguages(["de"]).download, "Download")
    }
}
