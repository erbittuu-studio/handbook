import Foundation

/// One analytics event.
public protocol SYSAnalyticsEvent {
    var name: String { get }
    var parameters: [String: Any] { get }
}

public extension SYSAnalyticsEvent {
    internal var parameters: [String: Any] { [:] }
}

/// Where events actually go.
public protocol SYSAnalyticsBackend: AnyObject {
    func configure()
    func log(name: String, parameters: [String: Any])
    func setUserID(_ id: String?)
    func setUserProperty(_ value: String?, for name: String)
}

/// The shared analytics entry point.
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

    var isEnabled: Bool {
        get { state.value.isEnabled }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    public init() {}

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

    func setUserID(_ id: String?) {
        guard isEnabled else { return }
        state.value.backend?.setUserID(id)
    }

    func setUserProperty(_ value: String?, for name: String) {
        guard isEnabled else { return }
        state.value.backend?.setUserProperty(value, for: name)
    }
}
