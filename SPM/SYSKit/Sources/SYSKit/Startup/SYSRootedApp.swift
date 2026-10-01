#if os(iOS) && canImport(Combine)
import CoreSpotlight
import SwiftUI

@MainActor
public protocol SYSRootedApp: SYSBootstrappedApp where Screen == AnyView {
    associatedtype Splash: View
    associatedtype Onboarding: View
    associatedtype Home: View

    @ViewBuilder func splash(progress: SYSAssetProgress?) -> Splash
    @ViewBuilder func onboarding(finish: @escaping () -> Void) -> Onboarding
    @ViewBuilder var home: Home { get }

    var blockerStyle: SYSLaunchBlockerStyle { get }
    var blockerText: SYSLaunchBlockerText { get }

    func homeReached()
    func open(_ url: URL)
    func openSpotlight(_ identifier: String)
}

@MainActor
public extension SYSRootedApp {
    func homeReached() {}
    func open(_ url: URL) {}
    func openSpotlight(_ identifier: String) {}

    func screen(for state: SYSAppState?) -> AnyView {
        #if DEBUG
        let state = SYSDebugRoute.launch?.name == "splash" ? nil : state
        #endif
        return AnyView(
            ZStack { route(state) }
                .animation(SYSMotion.standard, value: state)
                .sysOnChange(of: isHome(state)) { reached in
                    if reached { homeReached() }
                }
                .onOpenURL { open($0) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    openSpotlight(identifier)
                }
        )
    }

    private func isHome(_ state: SYSAppState?) -> Bool {
        switch state {
        case .ready, .whatsNew: return true
        default: return false
        }
    }

    @ViewBuilder
    private func route(_ state: SYSAppState?) -> some View {
        switch state {
        case .maintenance, .updateRequired, .dataUnavailable:
            if let state {
                blocker(for: state, style: blockerStyle, text: blockerText)
            }
        case .onboarding:
            onboarding(finish: {
                SYSOnboarding.markSeen()
                startup.advance()
            })
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))
        case .ready, .whatsNew:
            home.transition(.opacity)
        case .none:
            splash(progress: startup.progress).transition(.opacity)
        }
    }
}

@MainActor
public extension SYSRootedApp where Onboarding == EmptyView {
    func onboarding(finish: @escaping () -> Void) -> EmptyView { EmptyView() }
}
#endif
