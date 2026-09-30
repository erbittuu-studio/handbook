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

    private func fold(active: Bool, x: CGFloat = 190, width: CGFloat = 20) -> SYSRegion {
        SYSRegion(kind: .division, frame: CGRect(x: x, y: 0, width: active ? width : 0, height: 800), isActive: active)
    }

    func testAFlatFoldableHasAFoldButIsNotFolded() {
        var m = metrics(400, 800)
        XCTAssertFalse(m.hasFold)
        m.regions = [fold(active: false)]
        XCTAssertTrue(m.hasFold)
        XCTAssertFalse(m.isFolded)
        XCTAssertEqual(m.usableFrames, [m.contentFrame])
    }

    func testAnActiveFoldSplitsTheUsableArea() {
        var m = metrics(400, 800)
        m.regions = [fold(active: true)]
        XCTAssertTrue(m.isFolded)
        XCTAssertEqual(m.usableFrames, [
            CGRect(x: 0, y: 0, width: 190, height: 800),
            CGRect(x: 210, y: 0, width: 190, height: 800)
        ])
    }

    func testAHorizontalFoldSplitsTopAndBottom() {
        var m = metrics(400, 800)
        m.regions = [SYSRegion(kind: .division, frame: CGRect(x: 0, y: 390, width: 400, height: 20), isActive: true)]
        XCTAssertEqual(m.usableFrames, [
            CGRect(x: 0, y: 0, width: 400, height: 390),
            CGRect(x: 0, y: 410, width: 400, height: 390)
        ])
    }

    func testOnlyActiveOcclusionsAreReported() {
        var m = metrics(400, 800)
        let camera = CGRect(x: 300, y: 0, width: 60, height: 40)
        m.regions = [
            SYSRegion(kind: .occlusion, frame: camera, isActive: true),
            SYSRegion(kind: .occlusion, frame: CGRect(x: 10, y: 0, width: 30, height: 30), isActive: false)
        ]
        XCTAssertEqual(m.occlusions, [camera])
        XCTAssertFalse(m.hasFold)
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
