import XCTest
@testable import SYSKit

final class SYSTimingTests: XCTestCase {
    func testStaggerGrowsByTheStepAndNeverGoesNegative() {
        XCTAssertEqual(SYSTiming.stagger(0), 0)
        XCTAssertEqual(SYSTiming.stagger(3), 3 * SYSTiming.staggerStep, accuracy: 0.0001)
        XCTAssertEqual(SYSTiming.stagger(2, step: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(SYSTiming.stagger(-4), 0)
    }

    func testPauseTreatsNegativeAsZero() async {
        await SYSTiming.pause(-1)
    }

    @MainActor
    func testAfterRunsTheActionOnTheMainActor() async {
        let ran = expectation(description: "ran")
        SYSTiming.after(0.01) { ran.fulfill() }
        await fulfillment(of: [ran], timeout: 2)
    }

    @MainActor
    func testACancelledDelayNeverRuns() async {
        let ran = expectation(description: "ran")
        ran.isInverted = true
        let task = SYSTiming.after(0.05) { ran.fulfill() }
        task.cancel()
        await fulfillment(of: [ran], timeout: 0.3)
    }
}
