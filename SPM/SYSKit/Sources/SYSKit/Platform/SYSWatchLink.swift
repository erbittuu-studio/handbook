#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// The link between an iPhone app and its Apple Watch app: each side hands over small named pieces of data and the other side is told when they change.
@MainActor
public final class SYSWatchLink: NSObject {
    public static let shared = SYSWatchLink()

    private var latest: [String: Data] = [:]
    private var observers: [String: [(Data) -> Void]] = [:]
    private var started = false

    override init() {
        super.init()
    }

    public func start() {
        guard !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func observe(_ key: String, _ handler: @escaping (Data) -> Void) {
        observers[key, default: []].append(handler)
        let session = WCSession.default
        if session.activationState == .activated, let existing = session.receivedApplicationContext[key] as? Data {
            handler(existing)
        }
    }

    public func send(_ data: Data, for key: String) {
        latest[key] = data
        push()
    }

    private func push() {
        guard started, WCSession.default.activationState == .activated else { return }
        do {
            try WCSession.default.updateApplicationContext(latest)
        } catch {
            SYSLogger.debug("watch link: could not send \(error)")
        }
    }

    private func receive(_ values: [String: Data]) {
        for (key, data) in values {
            observers[key]?.forEach { $0(data) }
        }
    }
}

extension SYSWatchLink: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let waiting = session.receivedApplicationContext.compactMapValues { $0 as? Data }
        Task { @MainActor in
            self.push()
            self.receive(waiting)
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let values = applicationContext.compactMapValues { $0 as? Data }
        Task { @MainActor in self.receive(values) }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#else
import Foundation

/// The link between an iPhone app and its Apple Watch app; on platforms without a watch it does nothing.
@MainActor
public final class SYSWatchLink {
    public static let shared = SYSWatchLink()

    init() {}

    public func start() {}

    public func observe(_ key: String, _ handler: @escaping (Data) -> Void) {}

    public func send(_ data: Data, for key: String) {}
}
#endif
