import XCTest
@testable import SYSKit

final class SYSAppCatalogLabelTests: XCTestCase {
    private func catalog(labels: [String: [String: String]]?) -> SYSAppCatalog {
        let catalog = SYSAppCatalog()
        catalog.applyForTesting(SYSAppCatalogData(version: 1, baseUrl: nil, apps: [], labels: labels))
        return catalog
    }

    func testLabelComesFromTheCatalogInTheRequestedLanguage() {
        let sut = catalog(labels: ["get": ["en": "Get", "hi": "पाएँ"]])
        XCTAssertEqual(sut.label("get", for: ["hi"], fallback: "Get"), "पाएँ")
    }

    func testLabelFallsBackToEnglishThenToTheGivenWord() {
        let sut = catalog(labels: ["get": ["en": "Get"]])
        XCTAssertEqual(sut.label("get", for: ["gu"], fallback: "Download"), "Get")
        XCTAssertEqual(sut.label("open", for: ["en"], fallback: "Open"), "Open")
    }

    func testNoLabelsAtAllUsesTheFallback() {
        XCTAssertEqual(catalog(labels: nil).label("get", fallback: "Get"), "Get")
    }
}
