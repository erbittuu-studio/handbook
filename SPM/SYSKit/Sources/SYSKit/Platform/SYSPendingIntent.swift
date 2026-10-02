@MainActor
/// Holds one intent until the app is actually ready to act on it.
public final class SYSPendingIntent<Intent> {
    private var queued: Intent?
    private var deliver: ((Intent) -> Void)?

    public init() {}

    public func receive(_ intent: Intent) {
        if let deliver {
            deliver(intent)
        } else {
            queued = intent
        }
    }

    public func markReady(deliver: @escaping (Intent) -> Void) {
        self.deliver = deliver
        if let queued {
            self.queued = nil
            deliver(queued)
        }
    }

    func reset() {
        deliver = nil
    }
}
