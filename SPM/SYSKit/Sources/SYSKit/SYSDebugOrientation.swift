#if os(iOS)
import UIKit

public extension SYSDebugRoute {
    @MainActor
    static func applyLaunchOrientation() {
        #if DEBUG
        guard #available(iOS 16.0, *),
              let value = value(of: "-debugOrientation", in: CommandLine.arguments),
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        let mask: UIInterfaceOrientationMask = value == "landscape" ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        #endif
    }
}
#endif
