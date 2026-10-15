import Combine
import XCTest
@testable import SYSKit

@MainActor
final class SYSConnectivityTests: XCTestCase {

    private func makeConnectivity() -> SYSConnectivity {
        SYSConnectivity(monitor: nil)
    }

    func testStartsOnlineSoLaunchNeverFlashesOffline() {
        let connectivity = makeConnectivity()
        XCTAssertTrue(connectivity.isOnline)
        XCTAssertFalse(connectivity.isExpensive)
        XCTAssertFalse(connectivity.isConstrained)
    }

    func testGoingOfflineAndBack() {
        let connectivity = makeConnectivity()
        connectivity.update(isOnline: false)
        XCTAssertFalse(connectivity.isOnline)
        connectivity.update(isOnline: true)
        XCTAssertTrue(connectivity.isOnline)
    }

    func testOptionalDownloadsNeedAnUnrestrictedPath() {
        let connectivity = makeConnectivity()
        XCTAssertTrue(connectivity.allowsOptionalDownloads)

        connectivity.update(isOnline: true, isExpensive: true)
        XCTAssertFalse(connectivity.allowsOptionalDownloads, "cellular or hotspot")

        connectivity.update(isOnline: true, isConstrained: true)
        XCTAssertFalse(connectivity.allowsOptionalDownloads, "Low Data Mode")

        connectivity.update(isOnline: false)
        XCTAssertFalse(connectivity.allowsOptionalDownloads, "no network")
    }

    func testPublishesOnlyWhenSomethingChanges() {
        let connectivity = makeConnectivity()
        var changes = 0
        let subscription = connectivity.objectWillChange.sink { changes += 1 }

        connectivity.update(isOnline: true)
        XCTAssertEqual(changes, 0, "same values must not redraw views")

        connectivity.update(isOnline: false)
        XCTAssertGreaterThan(changes, 0)
        subscription.cancel()
    }
}
