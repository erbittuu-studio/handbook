import XCTest
@testable import SYSKit

final class SYSLinksTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SYSHosting.usesLocalContent = true
    }

    override func tearDown() {
        SYSHosting.usesLocalContent = true
        SYSHosting.resetForTesting()
        super.tearDown()
    }

    private func config(_ json: String) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(contentID: "abclearning"))
        // Decoding a compile-time literal fixture; cannot fail.
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    func testLinksListKeepsTheOrderOfTheConfig() {
        let sut = config(#"""
        {"links":[
          {"id":"website","url":"https://example.com/apps"},
          {"id":"support","url":"https://example.com/support"}
        ]}
        """#)
        XCTAssertEqual(sut.links().map(\.id), ["website", "support"])
    }

    func testWebsiteAddressAloneGivesAllFourLinks() {
        let sut = config(#"{"urls":{"website":"https://example.com/apps"}}"#)
        XCTAssertEqual(sut.links().map(\.id), ["support", "privacy", "terms", "website"])
        XCTAssertEqual(sut.links().map(\.url.absoluteString), [
            "https://example.com/apps/abclearning/support",
            "https://example.com/apps/abclearning/privacy",
            "https://example.com/apps/abclearning/terms",
            "https://example.com/apps"
        ])
    }

    func testAnAddressInTheUrlsTableBeatsTheComputedOne() {
        let sut = config(#"{"urls":{"website":"https://example.com/apps","support":"https://help.example.com"}}"#)
        XCTAssertEqual(sut.links().first { $0.id == "support" }?.url.absoluteString, "https://help.example.com")
        XCTAssertEqual(sut.links().first { $0.id == "privacy" }?.url.absoluteString, "https://example.com/apps/abclearning/privacy")
    }

    func testWithoutAWebsiteOnlyTheWrittenAddressesAreShown() {
        let sut = config(#"{"urls":{"terms":"https://example.com/t","support":"https://example.com/s","other":"https://example.com/o"}}"#)
        XCTAssertEqual(sut.links().map(\.id), ["support", "terms"])
    }

    func testTitlesComeInTheRequestedLanguageWithNothingInTheConfig() {
        let sut = config(#"{"urls":{"website":"https://example.com/apps"}}"#)
        XCTAssertEqual(sut.links(for: ["hi"]).map(\.title), ["सहायता", "गोपनीयता नीति", "उपयोग की शर्तें", "वेबसाइट"])
        XCTAssertEqual(sut.linksTitle(for: ["ja"]), "情報")
    }

    func testStandardLinksHaveEnglishTitlesAndSymbols() {
        let sut = config(#"{"links":[{"id":"privacy","url":"https://example.com/p"}]}"#)
        XCTAssertEqual(sut.links().first?.title, "Privacy Policy")
        XCTAssertEqual(sut.links().first?.symbol, "hand.raised.fill")
    }

    func testTitleComesFromTheConfigInTheRequestedLanguage() {
        let sut = config(#"{"links":[{"id":"privacy","title":{"en":"Privacy Policy","hi":"गोपनीयता नीति"},"url":"https://example.com/p"}]}"#)
        XCTAssertEqual(sut.links(for: ["hi"]).first?.title, "गोपनीयता नीति")
        XCTAssertEqual(sut.links(for: ["gu"]).first?.title, "Privacy Policy")
    }

    func testCustomLinkKeepsItsOwnTitleAndSymbol() {
        let sut = config(#"{"links":[{"id":"faq","title":{"en":"Questions"},"symbol":"questionmark.circle","url":"https://example.com/faq"}]}"#)
        XCTAssertEqual(sut.links().first?.title, "Questions")
        XCTAssertEqual(sut.links().first?.symbol, "questionmark.circle")
    }

    func testDisabledLinkIsLeftOut() {
        let sut = config(#"{"links":[{"id":"terms","enabled":false,"url":"https://example.com/t"},{"id":"support","url":"https://example.com/s"}]}"#)
        XCTAssertEqual(sut.links().map(\.id), ["support"])
    }

    func testOnlyHttpsAddressesAreKept() {
        let sut = config(#"{"links":[{"id":"a","url":"http://example.com"},{"id":"b","url":"javascript:alert(1)"},{"id":"c","url":"https://example.com"}]}"#)
        XCTAssertEqual(sut.links().map(\.id), ["c"])
    }

    func testRelativeAddressResolvesAgainstTheAppsContentFolder() {
        let sut = config(#"{"links":[{"id":"support","url":"Web/support.html"}]}"#)
        XCTAssertEqual(sut.links().first?.url.absoluteString, "\(SYSHosting.baseURL)/abclearning/Web/support.html")
    }

    func testNoLinksAndNoUrlsGivesAnEmptyList() {
        XCTAssertTrue(config("{}").links().isEmpty)
    }

    func testSectionTitleComesFromTheConfig() {
        let sut = config(#"{"linksTitle":{"en":"About","hi":"जानकारी"}}"#)
        XCTAssertEqual(sut.linksTitle(for: ["hi"]), "जानकारी")
        XCTAssertEqual(config("{}").linksTitle(), "About")
    }
}
