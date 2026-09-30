#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// The system share sheet, presented correctly on both idioms.
///
/// `UIActivityViewController` has two traps, and the apps here fell into one
/// each.
///
/// **The popover must be pointed at something.** On iPad the sheet is a
/// popover, and one presented with no `sourceView` raises rather than degrading
/// to anything. Setting `permittedArrowDirections` alone does not satisfy it —
/// arrowless is still sourceless, and that mistake survived in a file whose own
/// comment described the rule.
///
/// **`connectedScenes.first` is not the scene the user is looking at.** The set
/// is unordered and includes background and disconnecting scenes, so presenting
/// from it reaches a window nobody can see — rarely, on a device with more than
/// one window, which is to say on the reviewer's iPad and not on yours.
/// `windows.first` has the same problem one level down: the first window is not
/// necessarily the key one.
///
/// Both are handled here once. Two entry points, because the apps genuinely
/// differ: a SwiftUI `.sheet` wants a view, a button action wants a function.
public enum SYSShare {

    /// The foreground-active scene, or nil when the app is not frontmost.
    @MainActor
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    /// Presents the share sheet over whatever is on screen.
    ///
    /// - Parameters:
    ///   - items: what to share — a String, URL, UIImage, or anything else
    ///     UIActivityViewController accepts.
    ///   - completion: called with the chosen activity type when the user
    ///     completes a share, and with nil when they cancel. Use it to record
    ///     the outcome; recording at presentation time counts every dismissal
    ///     as a share.
    /// - Returns: whether a sheet was presented.
    @MainActor
    @discardableResult
    public static func present(
        _ items: [Any],
        completion: ((String?) -> Void)? = nil
    ) -> Bool {
        guard let scene = activeScene,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController
        else {
            SYSLogger.info("share: no active scene — not presenting")
            return false
        }

        // Present from the top of the stack: presenting from a controller that
        // is already presenting something silently does nothing.
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            completion?(completed ? (activityType?.rawValue ?? "unknown") : nil)
        }
        anchor(controller, to: presenter.view)
        presenter.present(controller, animated: true)
        return true
    }

    /// Points a popover at a view, centred and arrowless.
    ///
    /// Centring is right for a sheet with no originating button; a call site
    /// that has one should set `sourceRect` itself afterwards.
    @MainActor
    static func anchor(_ controller: UIActivityViewController, to view: UIView?) {
        guard let popover = controller.popoverPresentationController,
              popover.sourceView == nil,
              let view else { return }
        popover.permittedArrowDirections = []
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
    }
}

/// The share sheet as a view, for `.sheet(isPresented:)`.
///
/// The imperative `SYSShare.present` is usually simpler. This exists for a
/// call site that already models presentation as SwiftUI state.
public struct SYSShareSheet: UIViewControllerRepresentable {
    private let items: [Any]
    private let completion: ((String?) -> Void)?

    public init(items: [Any], completion: ((String?) -> Void)? = nil) {
        self.items = items
        self.completion = completion
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, _ in
            completion?(completed ? (activityType?.rawValue ?? "unknown") : nil)
        }
        return controller
    }

    /// Anchored here rather than in `make`: the controller has no view until
    /// SwiftUI has put it somewhere, and its own view is the anchor.
    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        SYSShare.anchor(controller, to: controller.view)
    }
}
#endif
