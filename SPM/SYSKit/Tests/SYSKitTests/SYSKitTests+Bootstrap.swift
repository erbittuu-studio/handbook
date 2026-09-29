import XCTest
@testable import SYSKit

// MARK: - SYSBootstrap.start(prepareContent:) — the SYSContentSync injection seam

/// `SYSBootstrap` defaults `prepareContent`/`pruneContent` to `SYSAssets`, so
/// every app already wired to it needs no changes. These tests exist for the
/// other half: an app on `SYSContentSync` passes its own closure instead, and
/// that closure — not `SYSAssets` — has to be what actually decides the
/// resulting `SYSAppState`.
@MainActor
final class SYSBootstrapContentInjectionTests: XCTestCase {
    private func config(version: Int = 1) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(contentID: "test-app"))
        // A config already held, so `start` doesn't try a real network fetch
        // for it — only `prepareContent` is under test here.
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(#"{"version":\#(version)}"#.utf8)))
        return config
    }

    func testCustomPrepareContentDrivesReadyState() async {
        let state = await SYSBootstrap.start(
            config: config(),
            onboardingEnabled: false,
            requiresAssets: true,
            requiresConfig: false,
            prepareContent: { _ in .success(()) }
        )
        XCTAssertEqual(state, .ready)
    }

    func testCustomPrepareContentFailureBecomesDataUnavailable() async {
        let state = await SYSBootstrap.start(
            config: config(),
            onboardingEnabled: false,
            requiresAssets: true,
            requiresConfig: false,
            prepareContent: { _ in .failure(.offline) }
        )
        XCTAssertEqual(state, .dataUnavailable(.offline))
    }

    func testPrepareContentIsNeverCalledWhenAssetsAreNotRequired() async {
        var called = false
        _ = await SYSBootstrap.start(
            config: config(),
            onboardingEnabled: false,
            requiresAssets: false,
            requiresConfig: false,
            prepareContent: { _ in called = true; return .success(()) }
        )
        XCTAssertFalse(called)
    }

    func testPruneContentRunsOnlyAfterPrepareSucceeds() async {
        var pruned = false
        _ = await SYSBootstrap.start(
            config: config(),
            onboardingEnabled: false,
            requiresAssets: true,
            requiresConfig: false,
            prepareContent: { _ in .failure(.offline) },
            pruneContent: { pruned = true }
        )
        XCTAssertFalse(pruned, "pruning after a failed prepare would sweep content that never finished downloading")

        pruned = false
        _ = await SYSBootstrap.start(
            config: config(),
            onboardingEnabled: false,
            requiresAssets: true,
            requiresConfig: false,
            prepareContent: { _ in .success(()) },
            pruneContent: { pruned = true }
        )
        XCTAssertTrue(pruned)
    }

    func testRetryContentUsesTheInjectedCloserToo() async {
        let state = await SYSBootstrap.retryContent(
            config: config(),
            onboardingEnabled: false,
            requiresConfig: false,
            prepareContent: { _ in .success(()) }
        )
        XCTAssertEqual(state, .ready)
    }
}
