import Foundation

public struct SYSSplashDuration: Equatable, Sendable {
    let firstLaunch: TimeInterval
    let returning: TimeInterval

    init(firstLaunch: TimeInterval, returning: TimeInterval) {
        self.firstLaunch = firstLaunch
        self.returning = returning
    }

    public static let none = SYSSplashDuration(firstLaunch: 0, returning: 0)
    public static let standard = SYSSplashDuration(firstLaunch: 1.0, returning: 0)

    func remaining(isFirstLaunch: Bool, elapsed: TimeInterval) -> TimeInterval {
        max(0, (isFirstLaunch ? firstLaunch : returning) - elapsed)
    }
}
