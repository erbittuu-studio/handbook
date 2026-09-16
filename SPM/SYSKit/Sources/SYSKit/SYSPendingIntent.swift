/// Holds one intent until the app is actually ready to act on it.
///
/// A Home Screen shortcut, a Spotlight tap, a deep link, a notification tap —
/// all four can arrive on a cold launch, before the screen that would act on
/// them has appeared. Acting immediately reaches a view that isn't listening
/// yet, so the intent is lost; three different ad-hoc fixes for this already
/// existed across our apps (a queued property with a manual drain, a blind
/// fixed delay, a readiness guard that just drops the intent) before this
/// type replaced all three with one.
///
/// Deliberately not wired to `SYSStartup` automatically. `SYSStartup.state ==
/// .ready` means the launch gates passed — maintenance, forced update,
/// required content — not that the view able to act on an intent has
/// mounted. Every app already has its own, later "home is actually showing"
/// signal on top of that (a splash-to-home transition, a navigation state),
/// and `markReady()` is meant to be called from there.
///
/// One instance per feature, holding that feature's own intent type — a
/// shortcut type, a pack id, a parsed deep-link target. Not a single shared
/// enum: those four sources resolve to genuinely different app-domain types,
/// and forcing them into one shape here would mean SYSKit inventing the
/// app's own domain, which is not its job.
@MainActor
public final class SYSPendingIntent<Intent> {
    private var queued: Intent?
    private var deliver: ((Intent) -> Void)?

    public init() {}

    /// Call from wherever the intent arrives. Delivered immediately once
    /// `markReady` has been called; queued before that. A second intent
    /// arriving before the first is delivered replaces it — the user acted
    /// again while the app was still loading, and wants that one, not both
    /// played back in sequence.
    public func receive(_ intent: Intent) {
        if let deliver {
            deliver(intent)
        } else {
            queued = intent
        }
    }

    /// Call exactly once, from the point the app already knows its real UI
    /// is on screen. Delivers a queued intent immediately if there is one.
    public func markReady(deliver: @escaping (Intent) -> Void) {
        self.deliver = deliver
        if let queued {
            self.queued = nil
            deliver(queued)
        }
    }

    /// Reverts to "not ready" — for an app that can legitimately go
    /// backward (a forced logout back to a splash, say). The previous
    /// `deliver` closure may have captured a view that is no longer current.
    public func reset() {
        deliver = nil
    }
}
