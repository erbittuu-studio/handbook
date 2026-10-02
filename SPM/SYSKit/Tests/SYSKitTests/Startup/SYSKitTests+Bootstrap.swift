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

@MainActor
final class SYSBootstrapGateTests: XCTestCase {
    private func config(_ json: String) -> SYSConfig {
        let config = SYSConfig(bundle: StubBundle(contentID: "test-app"))
        // swiftlint:disable:next force_try
        config.applyForTesting(try! JSONDecoder().decode(SYSConfigData.self, from: Data(json.utf8)))
        return config
    }

    func testGateIsOpenWithoutMaintenanceOrForcedUpdate() async {
        let state = await SYSBootstrap.gate(config: config(#"{"version":1}"#))
        XCTAssertNil(state)
    }

    func testGateClosesForMaintenance() async {
        let state = await SYSBootstrap.gate(config: config(#"{"version":1,"maintenance":{"enabled":true,"message":"Back soon"}}"#))
        XCTAssertEqual(state, .maintenance(message: "Back soon"))
    }

    func testStartDoesNotWaitForTheNetworkWhenConfigIsHeld() async {
        let started = Date()
        _ = await SYSBootstrap.start(
            config: config(#"{"version":1}"#),
            onboardingEnabled: false,
            prepareContent: { _ in .success(()) }
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }
}

final class SYSSplashDurationTests: XCTestCase {
    func testFirstLaunchWaitsLongerThanLaterOnes() {
        let duration = SYSSplashDuration.standard
        XCTAssertEqual(duration.remaining(isFirstLaunch: true, elapsed: 0), duration.firstLaunch)
        XCTAssertEqual(duration.remaining(isFirstLaunch: false, elapsed: 0), duration.returning)
        XCTAssertGreaterThan(duration.firstLaunch, duration.returning)
    }

    func testTimeAlreadySpentIsSubtracted() {
        let duration = SYSSplashDuration(firstLaunch: 2, returning: 1)
        XCTAssertEqual(duration.remaining(isFirstLaunch: true, elapsed: 0.5), 1.5, accuracy: 0.0001)
        XCTAssertEqual(duration.remaining(isFirstLaunch: false, elapsed: 0.25), 0.75, accuracy: 0.0001)
    }

    func testNeverNegative() {
        XCTAssertEqual(SYSSplashDuration.standard.remaining(isFirstLaunch: true, elapsed: 60), 0)
    }

    func testNoneNeverWaits() {
        XCTAssertEqual(SYSSplashDuration.none.remaining(isFirstLaunch: true, elapsed: 0), 0)
        XCTAssertEqual(SYSSplashDuration.none.remaining(isFirstLaunch: false, elapsed: 0), 0)
    }
}
