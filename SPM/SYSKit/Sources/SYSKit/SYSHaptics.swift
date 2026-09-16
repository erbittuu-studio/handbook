#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Haptic feedback, with the generators kept alive between taps.
///
/// The naive version is one line and every app writes it:
///
///     UIImpactFeedbackGenerator(style: .light).impactOccurred()
///
/// It works, and it is worse than it looks. A generator built for a single call
/// is deallocated straight after it, so the Taptic Engine is cold on the next
/// tap: the first one lags, and taps in quick succession get dropped entirely.
/// `prepare()` is what warms it, and there is nothing left to prepare when the
/// object is already gone. Two apps here wrote this independently and only one
/// of them cached — which is exactly the kind of difference nobody reports,
/// because a slightly late tap does not feel like a bug, it feels like the
/// phone.
///
/// So generators are held per style, reused, and re-prepared after firing.
///
/// Nothing here reads a setting. An app that offers a haptics toggle checks it
/// at the call site; a shared module guessing which setting means "no haptics"
/// would be wrong somewhere.
@MainActor
public enum SYSHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle:
                                          UIImpactFeedbackGenerator] = [:]

    /// A discrete change in a selection — a segment, a picker, a swatch.
    public static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Success, warning or error.
    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// A tap, at the given weight and, optionally, a shaped intensity — a
    /// second beat in a compound pattern reading as an echo of the first
    /// needs to land lighter than it, which is what `intensity` is for.
    /// `1.0` (the default) is a plain, full-strength tap.
    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1.0) {
        let generator = impactGenerators[style] ?? {
            let made = UIImpactFeedbackGenerator(style: style)
            impactGenerators[style] = made
            return made
        }()
        generator.impactOccurred(intensity: intensity)
        // Re-prepared straight after firing, which covers a run of taps. The
        // first tap after a pause needs warmUp().
        generator.prepare()
    }

    // Named weights, so a call site reads as intent rather than as UIKit.
    public static func light() { impact(.light) }
    public static func medium() { impact(.medium) }
    public static func heavy() { impact(.heavy) }
    public static func soft() { impact(.soft) }
    public static func rigid() { impact(.rigid) }

    public static func success() { notify(.success) }
    public static func warning() { notify(.warning) }
    public static func error() { notify(.error) }

    // MARK: Continuous gestures

    private static var lastTick = Date.distantPast

    /// A tick for a continuous gesture — a drag crossing regions, a scrubber
    /// passing marks.
    ///
    /// Rate-limited, and that is the whole point of it existing separately. A
    /// gesture crosses boundaries far faster than a hand means to, and one tick
    /// each turns the phone into a rattle. `interval` is the shortest gap that
    /// still reads as one tick per crossing.
    public static func tick(interval: TimeInterval = 0.08, style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= interval else { return }
        lastTick = now
        impact(style)
    }

    /// Forgets the rate-limit window and warms the generator, so the first tick
    /// of a gesture is immediate rather than late. Call when a gesture begins.
    public static func beginTicking(style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        lastTick = .distantPast
        prepare(style)
    }

    // MARK: Warming

    /// Prepares the generators an interaction is about to use.
    ///
    /// `prepare()` after firing covers a run of taps, but not the first one
    /// after a pause — the engine is idle and that tap lands late and weak.
    /// Calling this when a screen appears, or as a finger goes down, is what
    /// makes the first tap feel like the rest.
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
