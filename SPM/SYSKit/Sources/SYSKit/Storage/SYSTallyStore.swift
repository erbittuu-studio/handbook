#if canImport(Combine)
import Combine
import Foundation

/// A tally kept on the device and, when a watch link is given, in step with the same tally on the paired watch or phone.
@MainActor
public final class SYSTallyStore: ObservableObject {
    @Published public private(set) var tally: SYSTally

    private let defaults: UserDefaults
    private let storageKey: String
    private let device: String
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
        self.storageKey = "sys.tally.\(name)"
        self.link = link
        self.now = now
        self.device = Self.deviceID(defaults: .standard)
        self.tally = defaults.data(forKey: "sys.tally.\(name)")
            .flatMap { try? JSONDecoder().decode(SYSTally.self, from: $0) } ?? SYSTally()
        link?.start()
        link?.observe(storageKey) { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        resetObserver = NotificationCenter.default.publisher(for: .sysDidReset).sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    public var today: String { SYSTally.dayKey(now()) }

    public func total(of item: String) -> Int { tally.total(of: item) }

    public var countToday: Int { tally.count(on: today) }

    public var streak: Int { tally.streak(today: now()) }

    public func add(_ amount: Int, to item: String) {
        tally.add(amount, to: item, on: today, device: device)
        persist()
    }

    public func setTotal(of item: String, to value: Int) {
        tally.setTotal(of: item, to: value, on: today, device: device)
        persist()
    }

    func reload() {
        tally = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(SYSTally.self, from: $0) } ?? SYSTally()
    }

    func receive(_ data: Data) {
        guard let other = try? JSONDecoder().decode(SYSTally.self, from: data) else { return }
        var merged = tally
        merged.merge(other, today: today)
        guard merged != tally else { return }
        tally = merged
        save()
    }

    private func persist() {
        save()
        if let data = try? JSONEncoder().encode(tally) { link?.send(data, for: storageKey) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tally) { defaults.set(data, forKey: storageKey) }
    }

    private static func deviceID(defaults: UserDefaults) -> String {
        let key = "sys.tally.device"
        if let existing = defaults.string(forKey: key) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}
#endif
