import XCTest
@testable import SYSKit

final class SYSLaunchRecorderTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var time = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { time = time.addingTimeInterval(seconds) }
    }

    func testSummaryNeedsHome() {
        let recorder = SYSLaunchRecorder(processStart: nil)
        recorder.mark(.appLaunched)
        XCTAssertNil(recorder.summary)
    }

    func testFirstMarkWins() {
        let clock = Clock()
        let recorder = SYSLaunchRecorder(processStart: nil, now: { clock.time })
        XCTAssertTrue(recorder.mark(.startupBegan))
        clock.advance(5)
        XCTAssertFalse(recorder.mark(.startupBegan))
    }

    func testSummaryNamesEachPhase() {
        let clock = Clock()
        let recorder = SYSLaunchRecorder(processStart: clock.time.addingTimeInterval(-0.12), now: { clock.time })
        recorder.mark(.appLaunched)
        clock.advance(0.04)
        recorder.mark(.startupBegan)
        clock.advance(0.6)
        recorder.mark(.contentPrepared)
        clock.advance(0.5)
        recorder.mark(.ready)
        clock.advance(0.08)
        recorder.mark(.homeShown)
        XCTAssertEqual(
            recorder.summary,
            "launch: 1340 ms to home (process 120, startup 40, loading 600, splash hold 500, home 80)"
        )
    }

    func testWithoutProcessStartTotalRunsFromAppLaunch() {
        let clock = Clock()
        let recorder = SYSLaunchRecorder(processStart: nil, now: { clock.time })
        recorder.mark(.appLaunched)
        clock.advance(1)
        recorder.mark(.homeShown)
        XCTAssertEqual(recorder.summary, "launch: 1000 ms to home")
    }
}
