import Foundation

/// One analytics event. Apps declare their own conforming enum, so the vocabulary
/// stays app-specific while the plumbing below is shared.
public protocol SYSAnalyticsEvent {
    var name: String { get }
    var parameters: [String: Any] { get }
}

public extension SYSAnalyticsEvent {
    var parameters: [String: Any] { [:] }
}

/// Where events actually go. Implemented by SYSFirebase, so this package
/// needs no Firebase and stays testable without it.
public protocol SYSAnalyticsBackend: AnyObject {
    func configure()
    func log(name: String, parameters: [String: Any])
    func setUserID(_ id: String?)
    func setUserProperty(_ value: String?, for name: String)
}

/// The shared analytics entry point.
///
/// Only the event list differs per app; everything here — release-only sending,
/// the backend wiring, user properties — is identical, so it lives once.
public final class SYSAnalytics: @unchecked Sendable {
    public static let shared = SYSAnalytics()

    private struct State {
        var backend: SYSAnalyticsBackend?
        var isConfigured = false
        var isEnabled: Bool = {
            #if DEBUG
            return false
            #else
            return true
            #endif
        }()
    }

    private let state = SYSLocked(State())

    /// Sends events only in release builds by default, so day-to-day development
    /// never pollutes production analytics.
    public var isEnabled: Bool {
        get { state.value.isEnabled }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    public init() {}

    /// Call once at launch, before tracking anything.
    public func configure(backend: SYSAnalyticsBackend?) {
        let shouldConfigure = state.withLock { state -> Bool in
            guard !state.isConfigured else { return false }
            state.isConfigured = true
            state.backend = backend
            return state.isEnabled
        }
        guard shouldConfigure else { return }
        backend?.configure()
    }

    public func track(_ event: SYSAnalyticsEvent) {
        guard isEnabled else {
            SYSLogger.debug("[analytics] \(event.name) \(event.parameters)")
            return
        }
        state.value.backend?.log(name: event.name, parameters: event.parameters)
    }

    public func setUserID(_ id: String?) {
        guard isEnabled else { return }
        state.value.backend?.setUserID(id)
    }

    public func setUserProperty(_ value: String?, for name: String) {
        guard isEnabled else { return }
        state.value.backend?.setUserProperty(value, for: name)
    }
}
