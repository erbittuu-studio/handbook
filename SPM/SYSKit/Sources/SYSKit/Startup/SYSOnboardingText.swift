import Foundation

/// The words around the screens of a first-run flow. The app writes them in its own localization so SYSKit carries no strings.
/// Skip is optional: without it the flow has no Skip button and everyone sees every screen.
public struct SYSOnboardingText: Equatable, Sendable {
    public var next: String
    public var start: String
    public var done: String
    public var skip: String?

    public init(next: String, start: String, done: String, skip: String? = nil) {
        self.next = next
        self.start = start
        self.done = done
        self.skip = skip
    }
}
