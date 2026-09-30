import CoreGraphics
import XCTest
@testable import SYSKit

final class SYSMetricsTests: XCTestCase {
    private func metrics(
        _ width: CGFloat,
        _ height: CGFloat,
        safeArea: SYSInsets = .zero,
        reference: SYSMetrics.Reference = .phone
    ) -> SYSMetrics {
        SYSMetrics(size: CGSize(width: width, height: height), safeArea: safeArea, reference: reference)
    }

    func testScaleIsOneAtTheReference() {
        let m = SYSMetrics.atReference()
        XCTAssertEqual(m.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(m.s(10), 10)
        XCTAssertEqual(m.f(10), 10)
    }

    func testScaleIsTheSameInEitherOrientation() {
        XCTAssertEqual(metrics(393, 759).scale, metrics(759, 393).scale, accuracy: 0.0001)
        XCTAssertEqual(metrics(600, 900).scale, metrics(900, 600).scale, accuracy: 0.0001)
    }

    func testScaleIsClampedToTheReferenceRange() {
        XCTAssertEqual(metrics(2000, 4000).scale, 1.7, accuracy: 0.0001)
        XCTAssertEqual(metrics(100, 200).scale, 0.75, accuracy: 0.0001)
    }

    func testTheTighterAxisDrivesTheScale() {
        let m = metrics(786, 759)
        XCTAssertEqual(m.scale, 786.0 / 759.0, accuracy: 0.0001)
    }

    func testSafeAreaIsTakenOffBeforeScaling() {
        let m = metrics(393, 852, safeArea: SYSInsets(top: 59, bottom: 34))
        XCTAssertEqual(m.contentSize, CGSize(width: 393, height: 759))
        XCTAssertEqual(m.scale, 1, accuracy: 0.0001)
    }

    func testAsymmetricSafeAreaIsHandledPerEdge() {
        let m = metrics(800, 400, safeArea: SYSInsets(leading: 0, trailing: 100))
        XCTAssertEqual(m.contentSize.width, 700)
    }

    func testContentSizeNeverReachesZero() {
        let m = metrics(10, 10, safeArea: SYSInsets(top: 50, leading: 50, bottom: 50, trailing: 50))
        XCTAssertEqual(m.contentSize, CGSize(width: 1, height: 1))
        XCTAssertEqual(m.scale, 0.75, accuracy: 0.0001)
    }

    func testFontsScaleMoreGentlyThanLayout() {
        let m = metrics(2000, 4000)
        XCTAssertEqual(m.s(10), 17)
        XCTAssertEqual(m.f(10), 15)
        XCTAssertLessThan(m.f(10), m.s(10))
    }

    func testACustomReferenceReproducesAnAppsOwnBase() {
        let landscape = SYSMetrics.Reference(shortSide: 354, longSide: 718, scaleRange: 0.74 ... 1.7)
        let m = metrics(812, 375, safeArea: SYSInsets(top: 0, leading: 47, bottom: 21, trailing: 47), reference: landscape)
        XCTAssertEqual(m.contentSize, CGSize(width: 718, height: 354))
        XCTAssertEqual(m.scale, 1, accuracy: 0.0001)
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

    func testOnlyACompactWidthWithRegularHeightStacks() {
        var m = metrics(400, 800)
        XCTAssertFalse(m.prefersSideBySide)
        m.verticalClass = .compact
        XCTAssertTrue(m.prefersSideBySide)
        m.horizontalClass = .regular
        m.verticalClass = .regular
        XCTAssertTrue(m.prefersSideBySide)
        m.verticalClass = .compact
        XCTAssertTrue(m.prefersSideBySide)
    }

    func testColumnsFitTheWidth() {
        let m = metrics(400, 800)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16), 2)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, in: 1000), 6)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, in: 100), 1)
    }

    func testColumnsCanBeEvenWithAFloor() {
        let m = metrics(400, 800)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, even: true), 2)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, even: true, in: 1000), 6)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, even: true, in: 700), 4)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, minimumColumns: 2, even: true, in: 100), 2)
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

    func testColumnsAreEvenOnAnyDeviceWithAFoldEvenWhenFlat() {
        var m = metrics(700, 800)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16), 4)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, in: 520), 3)
        m.regions = [fold(active: false)]
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, in: 520), 2)
        XCTAssertEqual(m.columns(minimumWidth: 150, spacing: 16, even: false, in: 520), 3)
    }

    func testColumnsTolerateANonsensicalMinimum() {
        XCTAssertEqual(metrics(400, 800).columns(minimumWidth: 0), 1)
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
