import Foundation

public struct SYSSplashDuration: Equatable, Sendable {
    public let firstLaunch: TimeInterval
    public let returning: TimeInterval

    public init(firstLaunch: TimeInterval, returning: TimeInterval) {
        self.firstLaunch = firstLaunch
        self.returning = returning
    }

    public static let none = SYSSplashDuration(firstLaunch: 0, returning: 0)
    public static let standard = SYSSplashDuration(firstLaunch: 2.0, returning: SYSTiming.relaxed)

    public func remaining(isFirstLaunch: Bool, elapsed: TimeInterval) -> TimeInterval {
        max(0, (isFirstLaunch ? firstLaunch : returning) - elapsed)
    }
}
