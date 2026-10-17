import Foundation

/// What is on screen right now, so two prompts never meet: the suggestion popup and the system review request look at each other here.
@MainActor
enum SYSPromptTraffic {
    static var popupShowing = false
    static var lastReviewRequest: Date?
}
