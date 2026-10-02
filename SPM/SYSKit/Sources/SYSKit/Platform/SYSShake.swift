#if os(iOS)
import CoreMotion
import SwiftUI

@MainActor
private final class SYSShakeDetector: ObservableObject {
    private static let threshold = 2.5
    private static let sampleInterval: TimeInterval = 0.1
    private static let cooldown: TimeInterval = 1.0

    private let motion = CMMotionManager()
    private var lastShake = Date.distantPast
    var onShake: () -> Void = {}

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = Self.sampleInterval
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let force = sqrt(
                data.acceleration.x * data.acceleration.x
                + data.acceleration.y * data.acceleration.y
                + data.acceleration.z * data.acceleration.z
            )
            let now = Date()
            if force > Self.threshold, now.timeIntervalSince(self.lastShake) > Self.cooldown {
                self.lastShake = now
                self.onShake()
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }
}

private struct SYSOnShake: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void
    @StateObject private var detector = SYSShakeDetector()

    func body(content: Content) -> some View {
        content
            .onAppear { update() }
            .onDisappear { detector.stop() }
            .sysOnChange(of: isEnabled) { _ in update() }
    }

    private func update() {
        detector.onShake = action
        if isEnabled { detector.start() } else { detector.stop() }
    }
}

public extension View {
    /// Calls action when the device is shaken, while isEnabled is true and the view is on screen.
    func sysOnShake(isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(SYSOnShake(isEnabled: isEnabled, action: action))
    }
}
#endif
