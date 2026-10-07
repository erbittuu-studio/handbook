import CoreGraphics
import XCTest
@testable import SYSKit

final class SYSMetricsTests: XCTestCase {
    private func metrics(
        _ width: CGFloat,
        _ height: CGFloat,
        safeArea: SYSInsets = .zero
    ) -> SYSMetrics {
        SYSMetrics(size: CGSize(width: width, height: height), safeArea: safeArea)
    }

    func testSafeAreaIsTakenOffTheContentSize() {
        let m = metrics(393, 852, safeArea: SYSInsets(top: 59, bottom: 34))
        XCTAssertEqual(m.contentSize, CGSize(width: 393, height: 759))
        XCTAssertEqual(m.shortSide, 393)
    }

    func testAsymmetricSafeAreaIsHandledPerEdge() {
        let m = metrics(800, 400, safeArea: SYSInsets(leading: 0, trailing: 100))
        XCTAssertEqual(m.contentSize.width, 700)
    }

    func testContentSizeNeverReachesZero() {
        let m = metrics(10, 10, safeArea: SYSInsets(top: 50, leading: 50, bottom: 50, trailing: 50))
        XCTAssertEqual(m.contentSize, CGSize(width: 1, height: 1))
    }

    func testShortSideIsTheSameInEitherOrientation() {
        XCTAssertEqual(metrics(393, 759).shortSide, metrics(759, 393).shortSide)
    }

    func testSizeClassFlagsFollowTheClasses() {
        var m = metrics(400, 800)
        XCTAssertTrue(m.isCompactWidth)
        XCTAssertFalse(m.isCompactHeight)
        m.horizontalClass = .regular
        m.verticalClass = .compact
        XCTAssertFalse(m.isCompactWidth)
        XCTAssertTrue(m.isCompactHeight)
    }

    func testSideBySideFollowsTheShapeOfTheAreaNotTheSizeClass() {
        XCTAssertFalse(metrics(400, 800).prefersSideBySide)
        XCTAssertTrue(metrics(800, 400).prefersSideBySide)
        XCTAssertFalse(metrics(1000, 1000).prefersSideBySide)
        var tabletUpright = metrics(834, 1194)
        tabletUpright.horizontalClass = .regular
        tabletUpright.verticalClass = .regular
        XCTAssertFalse(tabletUpright.prefersSideBySide)
        var tabletOnItsSide = metrics(1194, 834)
        tabletOnItsSide.horizontalClass = .regular
        tabletOnItsSide.verticalClass = .regular
        XCTAssertTrue(tabletOnItsSide.prefersSideBySide)
    }

    func testSideBySideUsesTheAreaLeftAfterTheSafeArea() {
        let m = metrics(800, 700, safeArea: SYSInsets(leading: 120, trailing: 120))
        XCTAssertFalse(m.prefersSideBySide)
    }

    func testMarginCentresReadableWidth() {
        let m = metrics(900, 600)
        XCTAssertEqual(m.margin(readableWidth: 600), 150)
        XCTAssertEqual(m.margin(readableWidth: 1200), 0)
        XCTAssertEqual(m.margin(readableWidth: 900, minimum: 16), 16)
    }

    func testInsetsSumTheirEdges() {
        let insets = SYSInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        XCTAssertEqual(insets.horizontal, 6)
        XCTAssertEqual(insets.vertical, 4)
        XCTAssertEqual(SYSInsets.zero.horizontal, 0)
    }
}
