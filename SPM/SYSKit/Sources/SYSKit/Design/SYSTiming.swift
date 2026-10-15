import Foundation

public enum SYSTiming {
    public static let quick: TimeInterval = 0.15
    public static let standard: TimeInterval = 0.3
    public static let relaxed: TimeInterval = 0.5
    public static let staggerStep: TimeInterval = 0.06

    public static func stagger(_ index: Int, step: TimeInterval = staggerStep) -> TimeInterval {
        TimeInterval(max(0, index)) * step
    }

    public static func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    @discardableResult
    public static func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            await pause(seconds)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
