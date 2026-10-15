import Foundation

/// Something that keeps data in memory or on disk that a reset has to put back to the day of installation.
@MainActor
public protocol SYSResettable: AnyObject {
    func resetForFreshInstall()
}

/// The things that reset with the app. SYSKit's own stores add themselves, so an app wires nothing.
@MainActor
enum SYSResetRegistry {
    private final class Entry {
        weak var value: (any SYSResettable)?
        init(_ value: any SYSResettable) { self.value = value }
    }

    private static var entries: [Entry] = []

    static func register(_ item: any SYSResettable) {
        entries.removeAll { $0.value == nil }
        entries.append(Entry(item))
    }

    static func resetAll() {
        for entry in entries { entry.value?.resetForFreshInstall() }
    }
}
