#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
/// Haptic feedback, with the generators kept alive between taps.
public enum SYSHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle:
                                          UIImpactFeedbackGenerator] = [:]

    public static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        let generator = impactGenerators[style] ?? {
            let made = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = made
            return made
        }()
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    public static func light() { impact(.light) }
    public static func medium() { impact(.medium) }
    public static func heavy() { impact(.heavy) }
    public static func soft() { impact(.soft) }
    public static func rigid() { impact(.rigid) }

    public static func success() { notify(.success) }
    public static func warning() { notify(.warning) }
    public static func error() { notify(.error) }

    public static func echo(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .heavy, after delay: TimeInterval = 0.1) {
        impact(style)
        SYSTiming.after(delay) { impact(.medium, intensity: 0.5) }
    }

    public static func celebrate() {
        success()
        SYSTiming.after(0.12) { heavy() }
        SYSTiming.after(0.24) { impact(.medium, intensity: 0.6) }
        SYSTiming.after(0.36) { impact(.soft, intensity: 0.8) }
    }

    private static var lastTick = Date.distantPast

    static func tick(interval: TimeInterval = 0.08, style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= interval else { return }
        lastTick = now
        impact(style)
    }

    public static func warmUp(_ styles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light]) {
        selectionGenerator.prepare()
        styles.forEach(prepare)
    }

    private static func prepare(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = impactGenerators[style] ?? {
            let made = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = made
            return made
        }()
        generator.prepare()
    }
}
#endif
