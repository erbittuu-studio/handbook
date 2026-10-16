#if canImport(Combine)
import Combine
import Foundation

/// A few settings the phone and its watch share, where the newest change to each setting wins.
@MainActor
public final class SYSSyncedSettings: ObservableObject {
    struct Entry: Codable, Equatable, Sendable {
        var value: String
        var stamp: Date
    }

    @Published private(set) var entries: [String: Entry]

    private let defaults: UserDefaults
    private let storageKey: String
    private let link: SYSWatchLink?
    private let now: () -> Date
    private var resetObserver: AnyCancellable?

    public init(
        name: String,
        defaults: UserDefaults = .standard,
        link: SYSWatchLink? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.storageKey = "sys.settings.\(name)"
        self.link = link
        self.now = now
        self.entries = defaults.data(forKey: "sys.settings.\(name)")
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        link?.start()
        link?.observe(storageKey) { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        resetObserver = NotificationCenter.default.publisher(for: .sysDidReset).sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    public subscript(key: String) -> String? {
        entries[key]?.value
    }

    public func int(_ key: String) -> Int? {
        entries[key].flatMap { Int($0.value) }
    }

    public func set(_ value: String, for key: String) {
        guard entries[key]?.value != value else { return }
        entries[key] = Entry(value: value, stamp: now())
        save()
        if let data = try? JSONEncoder().encode(entries) { link?.send(data, for: storageKey) }
    }

    public func set(_ value: Int, for key: String) {
        set(String(value), for: key)
    }

    func reload() {
        entries = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func receive(_ data: Data) {
        guard let incoming = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        var merged = entries
        for (key, entry) in incoming where entry.stamp > (merged[key]?.stamp ?? .distantPast) {
            merged[key] = entry
        }
        guard merged != entries else { return }
        entries = merged
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: storageKey) }
    }
}
#endif
