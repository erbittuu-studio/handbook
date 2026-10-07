import XCTest
@testable import SYSKit

final class SYSDesignCanvasTests: XCTestCase {
    private let canvas = SYSDesignCanvas(
        size: CGSize(width: 812, height: 375),
        horizontalInsets: 94,
        verticalInsets: 21,
        scaleRange: 0.74...1.7
    )

    func testTheDesignScreenScalesToOne() {
        let metrics = SYSMetrics(size: CGSize(width: 812, height: 375), safeArea: SYSInsets(top: 0, leading: 47, bottom: 21, trailing: 47), canvas: canvas)
        XCTAssertEqual(metrics.scale, 1, accuracy: 0.001)
        XCTAssertEqual(metrics.s(20), 20)
    }

    func testABiggerScreenScalesUpButStopsAtTheRange() {
        let metrics = SYSMetrics(size: CGSize(width: 4000, height: 3000), canvas: canvas)
        XCTAssertEqual(metrics.scale, 1.7, accuracy: 0.001)
    }

    func testASmallerScreenScalesDownButStopsAtTheRange() {
        let metrics = SYSMetrics(size: CGSize(width: 200, height: 100), canvas: canvas)
        XCTAssertEqual(metrics.scale, 0.74, accuracy: 0.001)
    }

    func testFontsFollowOnlyPartOfTheScale() {
        let metrics = SYSMetrics(size: CGSize(width: 4000, height: 3000), canvas: canvas)
        XCTAssertEqual(metrics.f(100), 146)
        XCTAssertEqual(metrics.s(100), 170)
    }

    func testWithoutACanvasSizesAreUnchanged() {
        let metrics = SYSMetrics(size: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(metrics.scale, 1)
        XCTAssertEqual(metrics.s(20), 20)
        XCTAssertEqual(metrics.f(20), 20)
    }
}
