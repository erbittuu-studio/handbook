#if canImport(Combine)
import Combine
import Foundation

/// How much of the content every sync in the app still lacks on this device, so one notice can say so, and how far
/// the syncs that fetch by themselves have got, so one bar can show it.
@MainActor
public final class SYSContentReadiness: ObservableObject {
    public static let shared = SYSContentReadiness()

    @Published public private(set) var missing = 0
    @Published public private(set) var fetchTotal = 0
    @Published public private(set) var fetchMissing = 0
    @Published public private(set) var needsUnmetered = false

    struct Entry: Equatable {
        var missing: Int
        var total: Int
        var fetches: Bool
        var unmeteredOnly: Bool
    }

    private var perSync: [ObjectIdentifier: Entry] = [:]

    func report(_ sync: ObjectIdentifier, _ entry: Entry) {
        guard perSync[sync] != entry else { return }
        perSync[sync] = entry
        let entries = perSync.values
        missing = entries.map(\.missing).reduce(0, +)
        let fetching = entries.filter(\.fetches)
        fetchTotal = fetching.map(\.total).reduce(0, +)
        fetchMissing = fetching.map(\.missing).reduce(0, +)
        let pending = fetching.filter { $0.missing > 0 }
        needsUnmetered = !pending.isEmpty && pending.allSatisfy(\.unmeteredOnly)
    }
}
#endif
