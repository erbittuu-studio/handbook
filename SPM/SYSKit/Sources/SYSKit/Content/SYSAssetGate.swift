#if canImport(SwiftUI)
import SwiftUI

/// Waits for a piece of content before showing the screen that needs it, and
/// offers a way back when it does not arrive.
///
/// The state machine is the same in every app that downloads content: skip the
/// wait if it is already here, otherwise load, then show the thing or show a way
/// to try again. Written per app it goes wrong in small ways — a spinner that
/// flashes for work that was never going to happen, a retry that does not reset,
/// a failure that navigates away and loses where the user was.
///
/// ```swift
/// SYSAssetGate(
///     id: category.id,
///     isReady: { store.isLoaded(category.id) },
///     load: { await store.ensure(category: category.id) }
/// ) {
///     grid(for: category)
/// } loading: {
///     MyLoadingView()
/// } failed: { retry in
///     MyErrorView(retry: retry)
/// }
/// ```
///
/// Renders nothing of its own: all three states are the app's views. It owns
/// when they appear, not how they look.
public struct SYSAssetGate<Ready: View, Loading: View, Failed: View>: View {
    private let id: String
    private let isReady: () -> Bool
    private let load: () async -> Bool
    private let ready: () -> Ready
    private let loading: () -> Loading
    private let failed: (@escaping () -> Void) -> Failed

    @State private var phase: Phase

    private enum Phase: Equatable { case loading, ready, failed }

    /// - Parameters:
    ///   - id: identifies the content. Changing it reloads, so a paged container
    ///     loads the page the user moved to.
    ///   - isReady: true when the content is already in memory. Checked before
    ///     loading so revisiting a screen does not flash a loading state for work
    ///     that will not happen.
    ///   - load: fetches it; true on success.
    ///   - failed: receives a retry action to wire to a button.
    public init(
        id: String,
        isReady: @escaping () -> Bool,
        load: @escaping () async -> Bool,
        @ViewBuilder ready: @escaping () -> Ready,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder failed: @escaping (@escaping () -> Void) -> Failed
    ) {
        self.id = id
        self.isReady = isReady
        self.load = load
        self.ready = ready
        self.loading = loading
        self.failed = failed
        // Start in the phase the content is already in. Defaulting to `.loading`
        // meant an already-loaded screen rendered its loading state for a frame
        // before `onAppear` could correct it — a visible flick of "fetching…" on
        // a screen with nothing to fetch, which is exactly what checking
        // `isReady` up front was meant to avoid.
        _phase = State(initialValue: isReady() ? .ready : .loading)
    }

    public var body: some View {
        ZStack {
            switch phase {
            case .ready: ready()
            case .loading: loading()
            case .failed: failed { Task { await run(force: true) } }
            }
        }
        // Deliberately not `.task(id:)` — see SYSBootstrappedApp: that modifier's
        // opaque return type lives in SwiftUICore, which a package cannot link
        // against, and the failure only appears when archiving for a device.
        .onAppear { Task { await run() } }
        .onChange(of: id) { _ in Task { await run() } }
    }

    @MainActor
    private func run(force: Bool = false) async {
        if !force, isReady() {
            phase = .ready
            return
        }
        phase = .loading
        let ok = await load()
        withAnimation(.easeOut(duration: 0.2)) { phase = ok ? .ready : .failed }
    }
}
#endif
