import XCTest
@testable import SYSKit

@MainActor
final class SYSParentalGateTests: XCTestCase {
    func testChallengeHasDistinctNumbersAndAMatchingAnswer() {
        for _ in 0..<50 {
            let challenge = SYSParentalGateChallenge.make()
            XCTAssertEqual(challenge.numbers.count, 9)
            XCTAssertEqual(Set(challenge.numbers).count, 9)
            let expected = challenge.ask == .largest ? challenge.numbers.max() : challenge.numbers.min()
            XCTAssertEqual(challenge.answer, expected)
        }
    }

    func testRightAnswerRunsTheActionAfterTheDelay() async {
        let gate = SYSParentalGate(successDelay: 0)
        var ran = false
        gate.trigger { ran = true }
        XCTAssertTrue(gate.isPresented)

        XCTAssertTrue(gate.answer(gate.challenge?.answer ?? -1))
        XCTAssertFalse(gate.isPresented)
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(ran)
    }

    func testWrongAnswersCountDownAndThenCloseWithoutRunningTheAction() async {
        var events: [SYSParentalGateEvent] = []
        let gate = SYSParentalGate(maxAttempts: 3, successDelay: 0) { events.append($0) }
        var ran = false
        gate.trigger { ran = true }

        let wrong = (gate.challenge?.answer ?? 0) + 1000
        XCTAssertFalse(gate.answer(wrong))
        XCTAssertEqual(gate.attemptsLeft, 2)
        XCTAssertFalse(gate.answer(wrong))
        XCTAssertTrue(gate.isPresented)
        XCTAssertFalse(gate.answer(wrong))

        XCTAssertFalse(gate.isPresented)
        await Task.yield()
        XCTAssertFalse(ran)
        XCTAssertEqual(events, [.shown, .failed])
    }

    func testEachTriggerStartsFreshWithAllAttempts() {
        let gate = SYSParentalGate(maxAttempts: 3, successDelay: 0)
        gate.trigger {}
        gate.answer((gate.challenge?.answer ?? 0) + 1000)
        gate.cancel()

        gate.trigger {}
        XCTAssertEqual(gate.attemptsLeft, 3)
    }
}
