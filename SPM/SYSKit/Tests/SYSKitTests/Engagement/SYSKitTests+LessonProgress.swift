import XCTest
@testable import SYSKit

@MainActor
final class SYSLessonProgressTests: XCTestCase {
    private var settings: SYSSettings!
    private var suite: String!
    private let keys = SYSLessonProgressKeys(
        positions: SYSSettingsKey<[String: Int]>("test.positions", default: [:]),
        totals: SYSSettingsKey<[String: Int]>("test.totals", default: [:]),
        seeds: SYSSettingsKey<[String: Int]>("test.seeds", default: [:]),
        recent: SYSSettingsKey<[Int]>("test.recent", default: [])
    )

    override func setUp() {
        super.setUp()
        suite = "sys.lesson.tests.\(UUID().uuidString)"
        settings = SYSSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeProgress(recentLimit: Int = 5) -> SYSLessonProgress {
        SYSLessonProgress(keys: keys, settings: settings, recentLimit: recentLimit, debounce: 0)
    }

    func testFirstOpenStartsAtTheBeginning() {
        let progress = makeProgress()
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 0)
        XCTAssertFalse(progress.hasProgress(for: 1))
        XCTAssertNil(progress.continuation)
    }

    func testReopeningResumesWhereTheLearnerWas() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 6, total: 10)
        progress.flush()
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 6)
        XCTAssertEqual(progress.continuation, .init(id: 1, index: 6, total: 10))
    }

    func testFreshOpenDiscardsPositionAndReshuffles() {
        let progress = makeProgress()
        let first = progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 6, total: 10)
        progress.flush()
        let restarted = progress.begin(1, total: 10, fresh: true)
        XCTAssertEqual(restarted.index, 0)
        XCTAssertNotEqual(restarted.seed, first.seed)
        XCTAssertNil(progress.continuation)
    }

    func testFinishedLessonStartsFromTheBeginningNextTime() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 9, total: 10)
        progress.finish(1)
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 0)
        XCTAssertNil(progress.continuation)
    }

    func testClosingTheScreenAfterFinishingCannotBringBackTheLastCard() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 9, total: 10)
        progress.finish(1)

        progress.record(1, index: 9, total: 10)
        progress.flush()

        XCTAssertFalse(progress.hasProgress(for: 1))
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 0)
        XCTAssertNil(progress.continuation)
    }

    func testBeginningAgainReopensTheSessionForSaving() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.finish(1)
        progress.begin(1, total: 10, fresh: true)
        progress.record(1, index: 3, total: 10)
        progress.flush()
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 3)
    }

    func testResumingKeepsTheSameShuffle() {
        let progress = makeProgress()
        let first = progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 4, total: 10)
        progress.flush()
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).seed, first.seed)
    }

    func testPositionBeyondTheLessonIsBroughtBack() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 9, total: 10)
        progress.flush()
        XCTAssertEqual(progress.begin(1, total: 5, fresh: false).index, 0)
    }

    func testFlushSavesAtOnceSoAKillLosesNothing() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 7, total: 10)
        progress.flush()

        let relaunched = makeProgress()
        XCTAssertEqual(relaunched.continuation, .init(id: 1, index: 7, total: 10))
        XCTAssertEqual(relaunched.begin(1, total: 10, fresh: false).index, 7)
    }

    func testContinueIsTheMostRecentLessonThatStillHasAPosition() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 2, total: 10)
        progress.begin(2, total: 8, fresh: false)
        progress.record(2, index: 5, total: 8)
        progress.flush()
        XCTAssertEqual(progress.continuation?.id, 2)

        progress.finish(2)
        XCTAssertEqual(progress.continuation, .init(id: 1, index: 2, total: 10))

        progress.finish(1)
        XCTAssertNil(progress.continuation)
    }

    func testLessonOpenedButNotMovedThroughIsNotAContinuation() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        XCTAssertNil(progress.continuation)
    }

    func testRecentsAreNewestFirstWithoutRepeatsAndCapped() {
        let progress = makeProgress(recentLimit: 3)
        for id in [1, 2, 3, 2, 4] {
            progress.begin(id, total: 5, fresh: false)
        }
        XCTAssertEqual(progress.recentIDs, [4, 2, 3])
    }

    func testLessonsKeepTheirOwnPositions() {
        let progress = makeProgress()
        progress.begin(1, total: 10, fresh: false)
        progress.record(1, index: 3, total: 10)
        progress.begin(2, total: 10, fresh: false)
        progress.record(2, index: 8, total: 10)
        progress.flush()
        XCTAssertEqual(progress.begin(1, total: 10, fresh: false).index, 3)
        XCTAssertEqual(progress.begin(2, total: 10, fresh: false).index, 8)
    }
}

final class SYSSeededShuffleTests: XCTestCase {
    func testSameSeedGivesTheSameOrder() {
        let items = Array(1...30)
        let seed = SYSShuffleSeed(42)
        XCTAssertEqual(items.sysShuffled(seed: seed), items.sysShuffled(seed: seed))
    }

    func testDifferentSeedsGiveDifferentOrders() {
        let items = Array(1...30)
        XCTAssertNotEqual(items.sysShuffled(seed: SYSShuffleSeed(1)), items.sysShuffled(seed: SYSShuffleSeed(2)))
    }

    func testShuffleKeepsEveryItemExactlyOnce() {
        let items = Array(1...30)
        XCTAssertEqual(items.sysShuffled(seed: SYSShuffleSeed(7)).sorted(), items)
    }

    func testSmallListsAreSafe() {
        XCTAssertEqual([Int]().sysShuffled(seed: SYSShuffleSeed(1)), [])
        XCTAssertEqual([5].sysShuffled(seed: SYSShuffleSeed(1)), [5])
    }

    func testOrderIsPinnedSoASavedPositionStillMeansTheSameCard() {
        XCTAssertEqual(Array(1...8).sysShuffled(seed: SYSShuffleSeed(12345)), [3, 5, 2, 6, 8, 7, 4, 1])
    }
}
