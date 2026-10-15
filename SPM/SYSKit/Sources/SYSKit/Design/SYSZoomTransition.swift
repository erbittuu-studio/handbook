#if os(iOS)
import SwiftUI

private struct SYSZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

public extension EnvironmentValues {
    /// The namespace a zoom transition source and destination share; set it once near the root.
    var sysZoomNamespace: Namespace.ID? {
        get { self[SYSZoomNamespaceKey.self] }
        set { self[SYSZoomNamespaceKey.self] = newValue }
    }
}

/// What the system can do for the zoom transition between a source view and its destination.
public enum SYSZoom {
    /// Whether this system draws the zoom transition between a source and its destination (iOS 18 and later).
    public static var isAvailable: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}

public extension View {
    /// Marks a view as the origin of a zoom transition on iOS 18 and later; no change before.
    @ViewBuilder
    func sysZoomSource(
        id: String,
        in namespace: Namespace.ID?,
        background: Color = .clear,
        cornerRadius: CGFloat = SYSRadius.lg
    ) -> some View {
        if #available(iOS 18.0, *), let namespace {
            matchedTransitionSource(id: id, in: namespace) { configuration in
                configuration
                    .background(background)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            self
        }
    }

    /// Makes a pushed screen zoom out of the source with this id on iOS 18 and later; no change before.
    @ViewBuilder
    func sysZoomDestination(sourceID: String, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
#endif
