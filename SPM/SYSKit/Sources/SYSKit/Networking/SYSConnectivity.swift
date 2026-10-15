#if canImport(Combine) && canImport(Network)
import Combine
import Foundation
import Network

@MainActor
/// Whether the device has a usable network path right now.
public final class SYSConnectivity: ObservableObject {
    public static let shared = SYSConnectivity()

    @Published public private(set) var isOnline: Bool
    @Published private(set) var isExpensive: Bool
    @Published private(set) var isConstrained: Bool

    private let monitor: NWPathMonitor?

    public init(monitor: NWPathMonitor? = NWPathMonitor()) {
        self.monitor = monitor
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

    func update(isOnline: Bool, isExpensive: Bool = false, isConstrained: Bool = false) {
        if self.isOnline != isOnline { self.isOnline = isOnline }
        if self.isExpensive != isExpensive { self.isExpensive = isExpensive }
        if self.isConstrained != isConstrained { self.isConstrained = isConstrained }
    }

    public var allowsOptionalDownloads: Bool {
        isOnline && !isExpensive && !isConstrained
    }
}
#endif
