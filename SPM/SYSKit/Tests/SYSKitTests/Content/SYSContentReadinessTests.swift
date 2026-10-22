import XCTest
@testable import SYSKit

@MainActor
final class SYSContentReadinessTests: XCTestCase {
    private func entry(
        _ missing: Int,
        of total: Int,
        fetches: Bool = true,
        unmeteredOnly: Bool = false
    ) -> SYSContentReadiness.Entry {
        .init(missing: missing, total: total, fetches: fetches, unmeteredOnly: unmeteredOnly)
    }

    func testTheBarCountsOnlySyncsThatFetchByThemselves() {
        let readiness = SYSContentReadiness()
        let auto = NSObject()
        let manual = NSObject()
        readiness.report(ObjectIdentifier(auto), entry(2, of: 10))
        readiness.report(ObjectIdentifier(manual), entry(5, of: 5, fetches: false))
        XCTAssertEqual(readiness.missing, 7)
        XCTAssertEqual(readiness.fetchTotal, 10)
        XCTAssertEqual(readiness.fetchMissing, 2)
    }

    func testWaitingForWifiOnlyWhenEveryPendingSyncNeedsIt() {
        let readiness = SYSContentReadiness()
        let wifi = NSObject()
        let any = NSObject()
        readiness.report(ObjectIdentifier(wifi), entry(3, of: 4, unmeteredOnly: true))
        XCTAssertTrue(readiness.needsUnmetered)
        readiness.report(ObjectIdentifier(any), entry(1, of: 2))
        XCTAssertFalse(readiness.needsUnmetered)
        readiness.report(ObjectIdentifier(any), entry(0, of: 2))
        XCTAssertTrue(readiness.needsUnmetered)
        readiness.report(ObjectIdentifier(wifi), entry(0, of: 4, unmeteredOnly: true))
        XCTAssertFalse(readiness.needsUnmetered)
    }
}
