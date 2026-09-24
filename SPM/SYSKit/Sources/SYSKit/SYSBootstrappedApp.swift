#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

/// An `App` whose launch sequence is wired for it.
///
/// Conforming supplies the screens; this supplies the order they appear in and
/// the `.task` that starts everything. Forgetting the `.task` leaves the app on
/// its loading screen forever with nothing in the log to say why.
///
/// ```swift
/// @main
/// struct RealAIApp: App, SYSBootstrappedApp {
///     @StateObject var startup = SYSStartup(requiresAssets: true)
///
///     @ViewBuilder
///     func screen(for state: SYSAppState?) -> some View {
///         switch state {
///         case .none:  LoadingView(progress: startup.progress?.fraction)
///         case .ready: HomeView()
///         ...
///         }
///     }
/// }
/// ```
///
/// This renders nothing of its own — every pixel is still the app's.
///
/// An app that needs a scene shape this can't express (several windows,
/// commands, a document group) implements `body` itself and calls
/// `startup.begin` from its own `.task`.
///
/// **`decorate` is that same escape hatch.** The default `body` calls
/// `decorate(screen(for:))`, wraps the result in `AnyView`, then attaches its
/// own `.onAppear` outside that. A `decorate` override that chains its own
/// `.onAppear`/`.onChange` onto `root` *before* returning can end up with
/// modifiers that silently never fire — confirmed in production as a splash
/// screen stuck forever with content already downloaded. Modifiers chained
/// directly on a view, with no `AnyView` step in between, don't have this
/// problem. A `decorate` override that only wraps for styling (colors,
/// environment objects, a backdrop) is unaffected; implement `body` directly
/// instead when `.onAppear`/`.onChange` is actually needed there.
@MainActor
public protocol SYSBootstrappedApp: App {
    associatedtype Screen: View

    /// Declare as `@StateObject` so it survives redraws.
    var startup: SYSStartup { get }

    /// What to show for each startup state, including `nil` while it runs.
    @ViewBuilder func screen(for state: SYSAppState?) -> Screen

    /// Runs after a successful launch and *before* the state is published.
    func afterReady() async

    /// Wraps the root — colour scheme, environment objects, a backdrop.
    /// Defaults to no change. See the type doc comment before adding
    /// `.onAppear`/`.onChange` here.
    @ViewBuilder func decorate(_ content: Screen) -> AnyView

}

/// What a blocking state offers the user, if anything.
///
/// Wording and icon are the app's; whether a button appears at all is not —
/// a retry on a 404 or hash mismatch re-fetches the same failure, and an
/// update prompt with no store link is a dead end.
public enum SYSStateAction {
    /// Nothing useful to offer; show the message alone.
    case none
    /// Worth another attempt.
    case retry(() -> Void)
    /// Needs a newer build; the URL is the store page.
    case update(URL)
}

@MainActor
public extension SYSBootstrappedApp {
    func afterReady() async {}

    func decorate(_ content: Screen) -> AnyView { AnyView(content) }

    var body: some Scene {
        WindowGroup {
            decorate(screen(for: startup.state))
                // Not `.task`: its opaque return type lives in SwiftUICore,
                // which a Swift package can't link against, so a device
                // archive fails while the simulator build passes.
                // SwiftUI may call this more than once; begin() ignores repeats.
                .onAppear {
                    Task { await startup.begin(afterReady: afterReady) }
                }
                .modifier(SYSBackgroundAssetsResumer(startup: startup))
        }
    }

    /// Re-attempts a failed content download. Wire to the retry button.
    func retryStartup() {
        startup.retry(afterReady: afterReady)
    }

    /// Whether a blocking state has an action worth showing, and which.
    func action(for state: SYSAppState) -> SYSStateAction {
        switch state {
        case let .updateRequired(_, storeURL):
            return storeURL.map { .update($0) } ?? .none
        case let .dataUnavailable(error):
            return error.isRetryable ? .retry { retryStartup() } : .none
        default:
            return .none
        }
    }
}

/// Calls `resumeBackgroundAssets()` on every return to the foreground, so
/// `backgroundAssets` needs no per-app wiring at all — a download interrupted
/// by the app being backgrounded or killed picks up on its own.
private struct SYSBackgroundAssetsResumer: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let startup: SYSStartup

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { phase in
            if phase == .active {
                startup.resumeBackgroundAssets()
            }
        }
    }
}

#endif
