#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// The system share sheet, presented correctly on both idioms.
public enum SYSShare {
    @MainActor
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

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

        // Present from the top of the stack: a controller that is already presenting ignores another present
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

/// The share sheet as a view, for .sheet(isPresented:).
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

    public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        SYSShare.anchor(controller, to: controller.view)
    }
}
#endif
