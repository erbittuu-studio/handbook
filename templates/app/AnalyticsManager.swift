//
//  AnalyticsManager.swift
//  {{APP_NAME}}
//
//  The app's analytics vocabulary. The plumbing — release-only sending, the
//  Firebase wiring, user properties — lives in SYSKit and is shared; only this
//  list of events and screens differs per app.
//
//  This file's path is a fixed contract: scripts/ci/validate_config.py's sibling
//  validate_analytics_events.py greps exactly App/Source/Shared/AnalyticsManager.swift
//  on every PR. Moving or renaming it silently disables that check.
//

import Foundation
import SYSKit

// MARK: - Screens

/// Every screen tracked for feature-usage reporting (Firebase → Engage →
/// Screens). {{ EDIT — one case per real screen the app navigates to. }}
enum AnalyticsScreen: String {
    case home
}

// MARK: - Events

/// Every event this app can send.
///
/// Write cases as `case .x(let y)`, never `case let .x(y)`: the PR check splits
/// on `case .` and skips the `case let` form, so it would report success while
/// checking nothing.
enum AnalyticsEvent: SYSAnalyticsEvent {
    case screenView(AnalyticsScreen)
    case appOpened

    var name: String {
        switch self {
        case .screenView: return "screen_view"
        case .appOpened: return "app_opened"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .screenView(let screen):
            return ["screen_name": screen.rawValue, "screen_class": screen.rawValue]
        case .appOpened:
            return [:]
        }
    }
}

// MARK: - Manager

/// Thin wrapper over SYSAnalytics and the crash-report context.
///
/// Nothing here knows about Firebase: SYSFirebaseBackend is installed once at
/// launch and everything below goes through SYSKit. Debug builds still send
/// nothing — SYSAnalytics.isEnabled is false there — and log the event instead
/// of discarding it, so a developer can see what would have been sent.
enum AnalyticsManager {

    static func log(_ event: AnalyticsEvent) {
        SYSAnalytics.shared.track(event)
    }

    /// Logs a screen_view event and records the screen on the crash report, so
    /// a report shows which screen the user was on — the first question asked
    /// of one, and a filterable key rather than a line in a scrolling log.
    static func screen(_ screen: AnalyticsScreen) {
        log(.screenView(screen))
        SYSLogger.setContext(screen.rawValue, for: "current_screen")
    }

    /// Records the content currently open, so a crash report shows what it
    /// was. Pass `nil` on exit — recorded as empty, since Crashlytics has no
    /// way to unset a key once set.
    static func setCrashItem(_ itemId: String?) {
        SYSLogger.setContext(itemId, for: "current_item_id")
    }
}
