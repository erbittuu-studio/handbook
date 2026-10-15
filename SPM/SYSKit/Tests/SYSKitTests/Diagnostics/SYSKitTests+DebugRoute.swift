import XCTest
@testable import SYSKit

final class SYSDebugRouteTests: XCTestCase {
    func testAFlagFollowedByAValueIsParsed() {
        let route = SYSDebugRoute.parse(["App", "-debugRoute", "quiz"])
        XCTAssertEqual(route?.name, "quiz")
        XCTAssertNil(route?.id)
    }

    func testAnIdentifierFollowsTheSlash() {
        let route = SYSDebugRoute.parse(["-debugRoute", "reader/12"])
        XCTAssertEqual(route?.name, "reader")
        XCTAssertEqual(route?.id, "12")
    }

    func testOnlyTheFirstSlashSplits() {
        XCTAssertEqual(SYSDebugRoute.parse(["-debugRoute", "pack/a/b"])?.id, "a/b")
    }

    func testMissingOrEmptyValuesGiveNoRoute() {
        XCTAssertNil(SYSDebugRoute.parse([]))
        XCTAssertNil(SYSDebugRoute.parse(["-debugRoute"]))
        XCTAssertNil(SYSDebugRoute.parse(["-debugRoute", ""]))
        XCTAssertNil(SYSDebugRoute.parse(["-debugRoute", "/12"]))
    }

    func testTheTestRunnerLaunchesWithNoRoute() {
        XCTAssertNil(SYSDebugRoute.launch)
        XCTAssertNil(SYSAppState.debugForced)
    }

    func testAForcedStateNamesTheBlockingScreens() {
        XCTAssertEqual(SYSAppState.forced(by: ["-debugState", "maintenance"]), .maintenance(message: nil))
        XCTAssertEqual(SYSAppState.forced(by: ["-debugState", "offline"]), .dataUnavailable(.offline))
        if case .updateRequired(_, let url)? = SYSAppState.forced(by: ["-debugState", "update"]) {
            XCTAssertNotNil(url)
        } else {
            XCTFail("update should force the update screen")
        }
        XCTAssertNil(SYSAppState.forced(by: ["-debugState", "ready"]))
        XCTAssertNil(SYSAppState.forced(by: []))
    }

    func testEveryForcedStateBlocks() {
        for name in ["maintenance", "update", "offline"] {
            XCTAssertEqual(SYSAppState.forced(by: ["-debugState", name])?.isBlocking, true)
        }
    }
}
