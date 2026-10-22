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

    var quickActions: [SYSQuickAction] { get }

    func homeReached()
    func enter(_ entry: SYSEntry)
}

@MainActor
public extension SYSRootedApp {
    var quickActions: [SYSQuickAction] { [] }

    func homeReached() {}
    func enter(_ entry: SYSEntry) {}

    func screen(for state: SYSAppState?) -> AnyView {
        #if DEBUG
        let state = SYSDebugRoute.launch?.name == "splash" ? nil : state
        #endif
        return AnyView(
            ZStack { route(state) }
                .sysConnectionIndicator()
                .animation(SYSMotion.standard, value: state)
                .sysOnChange(of: isHome(state)) { reached in
                    if reached {
                        SYSLaunchMetrics.mark(.homeShown)
                        homeReached()
                        SYSTiming.after(SYSTiming.relaxed) { SYSEntries.shared.markReady { enter($0) } }
                    }
                }
                .onOpenURL { SYSEntries.shared.open($0) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    SYSEntries.shared.openSpotlight(identifier)
                }
                .task { SYSEntries.shared.registerQuickActions(quickActions) }
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
            splash(progress: startup.progress)
                .sysLaunchHandoff(Color("LaunchBackground"))
                .transition(.opacity)
        }
    }
}

@MainActor
public extension SYSRootedApp where Onboarding == EmptyView {
    func onboarding(finish: @escaping () -> Void) -> EmptyView { EmptyView() }
}
#endif
