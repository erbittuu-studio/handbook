#if canImport(Combine) && canImport(Network)
import Combine
import Foundation
import Network

/// Whether the device has a usable network path right now.
///
/// `SYSNetwork` fetches with retries and timeouts but does not say *why* a fetch
/// keeps failing. This answers that, so an app can show "you're offline" instead
/// of a spinner that never ends, and skip optional work when the network is
/// costly:
///
///     @ObservedObject var connectivity = SYSConnectivity.shared
///     if !connectivity.isOnline { OfflineBanner() }
///
/// `isExpensive` is cellular or a personal hotspot; `isConstrained` is Low Data
/// Mode. Both are hints to defer big downloads, not reasons to refuse to work.
///
/// It reports what the system's path monitor says, which is "a route exists",
/// not "the server answers". A captive portal still reads as online.
@MainActor
public final class SYSConnectivity: ObservableObject {

    /// One monitor for the whole app. Apps with a test seam construct their own.
    public static let shared = SYSConnectivity()

    @Published public private(set) var isOnline: Bool
    @Published public private(set) var isExpensive: Bool
    @Published public private(set) var isConstrained: Bool

    private let monitor: NWPathMonitor?

    /// - Parameter monitor: pass `nil` for a monitor that never changes by
    ///   itself, which is what tests use together with `update(...)`.
    public init(monitor: NWPathMonitor? = NWPathMonitor()) {
        self.monitor = monitor
        // Assume online until the system says otherwise: a false "offline" banner
        // at launch is worse than a moment of optimism.
        self.isOnline = true
        self.isExpensive = false
        self.isConstrained = false

        monitor?.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor in
                self?.update(isOnline: online, isExpensive: expensive, isConstrained: constrained)
            }
        }
        monitor?.start(queue: DispatchQueue(label: "sys.connectivity"))
    }

    deinit {
        monitor?.cancel()
    }

    /// Applies a new path. Public only so tests and previews can drive it.
    public func update(isOnline: Bool, isExpensive: Bool = false, isConstrained: Bool = false) {
        if self.isOnline != isOnline { self.isOnline = isOnline }
        if self.isExpensive != isExpensive { self.isExpensive = isExpensive }
        if self.isConstrained != isConstrained { self.isConstrained = isConstrained }
    }

    /// Whether optional, large downloads should go ahead right now.
    public var allowsOptionalDownloads: Bool {
        isOnline && !isExpensive && !isConstrained
    }
}
#endif
