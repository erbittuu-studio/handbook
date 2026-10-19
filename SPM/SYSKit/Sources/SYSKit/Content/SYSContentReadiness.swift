#if canImport(Combine)
import Combine
import Foundation

/// How much of the content every sync in the app still lacks on this device, so one notice can say so.
@MainActor
public final class SYSContentReadiness: ObservableObject {
    public static let shared = SYSContentReadiness()

    @Published public private(set) var missing = 0

    private var perSync: [ObjectIdentifier: Int] = [:]

    func report(_ sync: ObjectIdentifier, missing count: Int) {
        guard perSync[sync] != count else { return }
        perSync[sync] = count
        missing = perSync.values.reduce(0, +)
    }
}
#endif
