import FirebaseCore
import FirebaseCrashlytics
import Foundation
import SYSKit

/// `SYSErrorReporter` only, for an app that vendors Crashlytics but not
/// Analytics — the App Store Kids Category forbids third-party measurement
/// and ad SDKs, so an app in it cannot carry `FirebaseAnalytics` at all.
///
/// Does not conform to `SYSAnalyticsBackend` and installs no analytics
/// backend: `SYSAnalytics.shared.track(_:)` stays safe to call regardless —
/// with nothing configured it is the same no-op release builds already give
/// an unconfigured backend — this type simply never wires one in.
public final class SYSFirebaseCrashlyticsBackend: SYSErrorReporter {
    public init() {}

    /// Call once at launch. See `SYSFirebaseBackend.install()` for why
    /// `allApps` rather than `app()`, and why this is not gated on DEBUG the
    /// way analytics sending is: configuring is not the same as collecting,
    /// and a debug build with no reporter installed has nowhere for
    /// `SYSLogger.error` to report a non-fatal.
    public static func install() {
        let backend = SYSFirebaseCrashlyticsBackend()
        backend.configure()
        SYSLogger.reporter = backend
    }

    private func configure() {
        guard FirebaseApp.allApps?.isEmpty ?? true else { return }
        FirebaseApp.configure()
    }

    // MARK: SYSErrorReporter

    public func report(message: String, error: Error?) {
        if let error {
            Crashlytics.crashlytics().record(error: error, userInfo: ["message": message])
        } else {
            Crashlytics.crashlytics().record(
                error: NSError(domain: "SYSKit", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
            )
        }
    }

    public func breadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    /// `nil` is recorded as an empty value — Crashlytics has no operation to
    /// remove a key once set. See `SYSFirebaseBackend.setContext` for the
    /// same note.
    public func setContext(_ value: String?, for key: String) {
        Crashlytics.crashlytics().setCustomValue(value ?? "", forKey: key)
    }
}
