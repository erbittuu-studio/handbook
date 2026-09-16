import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation
import SYSKit

/// Connects SYSKit's protocols to Firebase.
///
/// The only file in the system that imports Firebase, which is what keeps SYSKit
/// itself dependency-free and testable without it.
public final class SYSFirebaseBackend: SYSAnalyticsBackend, SYSErrorReporter {
    public init() {}

    /// Wires Firebase into SYSKit. Call once at launch, before SYSBootstrap.
    ///
    /// Firebase is configured here rather than being left to
    /// `SYSAnalytics.configure`, which returns before touching the backend when
    /// sending is disabled — and sending is disabled in DEBUG so development
    /// never reaches production analytics.
    ///
    /// That is right for events and wrong for Firebase itself: it meant
    /// `FirebaseApp.configure()` was never called in a debug build, so
    /// Crashlytics was dead there even though `SYSLogger.reporter` had just
    /// been pointed at it, and every non-fatal recorded during development went
    /// nowhere. Configuring is not the same as collecting.
    ///
    /// `configure()` is idempotent, so `SYSAnalytics` calling it again in
    /// release costs nothing.
    public static func install() {
        let backend = SYSFirebaseBackend()
        backend.configure()
        SYSAnalytics.shared.configure(backend: backend)
        SYSLogger.reporter = backend
    }

    // MARK: SYSAnalyticsBackend

    /// Guarded on `allApps`, not on `app()`.
    ///
    /// `FirebaseApp.app()` *logs* when there is no default app yet — the
    /// I-COR000003 "the default Firebase app has not yet been configured, add
    /// `FirebaseApp.configure()`" warning — so asking it whether to configure
    /// printed a warning telling us to do the very thing we were about to do.
    /// It looked like a real fault at the top of every launch, and the advice in
    /// it was already taken on the next line.
    ///
    /// `allApps` answers the same question and says nothing. It is also still a
    /// question worth asking rather than a flag of our own: a host app that has
    /// configured Firebase for itself must not be configured a second time, and
    /// only Firebase knows that.
    public func configure() {
        guard FirebaseApp.allApps?.isEmpty ?? true else { return }
        FirebaseApp.configure()
    }

    public func log(name: String, parameters: [String: Any]) {
        Analytics.logEvent(name, parameters: parameters)
    }

    public func setUserID(_ id: String?) {
        Analytics.setUserID(id)
        Crashlytics.crashlytics().setUserID(id)
    }

    public func setUserProperty(_ value: String?, for name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    // MARK: SYSErrorReporter

    /// Non-fatals, so failures that never crash the app are still visible.
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

    /// Crashlytics' `setCustomValue` takes `Any`, not `Any?` — passing `nil`
    /// through is what the empty-value convention in the protocol doc exists
    /// to avoid.
    public func setContext(_ value: String?, for key: String) {
        Crashlytics.crashlytics().setCustomValue(value ?? "", forKey: key)
    }
}
