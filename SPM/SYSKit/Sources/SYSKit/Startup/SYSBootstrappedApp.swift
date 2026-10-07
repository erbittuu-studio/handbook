#if canImport(SwiftUI) && canImport(Combine)
import SwiftUI

@MainActor
/// An App whose launch sequence is wired for it.
public protocol SYSBootstrappedApp: App {
    associatedtype Screen: View

    var startup: SYSStartup { get }

    @ViewBuilder func screen(for state: SYSAppState?) -> Screen

    func afterReady() async

    @ViewBuilder func decorate(_ content: Screen) -> AnyView
}

enum SYSStateAction {
    case none
    case retry(() -> Void)
    case update(URL)
}

@MainActor
public extension SYSBootstrappedApp {
    func afterReady() async {}

    func decorate(_ content: Screen) -> AnyView { AnyView(content) }

    var body: some Scene {
        WindowGroup {
            decorate(screen(for: startup.state))
                // onAppear, not .task: .task's opaque type lives in SwiftUICore, which a package cannot link, so a device archive fails
                .onAppear {
                    Task { await startup.begin(afterReady: afterReady) }
                }
                .modifier(SYSBackgroundAssetsResumer(startup: startup))
        }
    }

    func retryStartup() {
        startup.retry(afterReady: afterReady)
    }

    internal func action(for state: SYSAppState) -> SYSStateAction {
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
