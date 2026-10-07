import Foundation
#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit)
import UIKit
#endif

public struct SYSShuffleSeed: Equatable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    static func random() -> SYSShuffleSeed {
        SYSShuffleSeed(UInt64.random(in: 1...UInt64.max))
    }
}

public extension Array {
    /// The same elements in an order fixed by seed: the same seed always gives the same order, so a lesson can be shuffled o...
    func sysShuffled(seed: SYSShuffleSeed) -> [Element] {
        var state = seed.value
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
        var result = self
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            let other = Int(next() % UInt64(index + 1))
            result.swapAt(index, other)
        }
        return result
    }
}

public struct SYSLessonProgressKeys: Sendable {
    public let positions: SYSSettingsKey<[String: Int]>
    let totals: SYSSettingsKey<[String: Int]>
    let seeds: SYSSettingsKey<[String: Int]>
    let recent: SYSSettingsKey<[Int]>

    public init(
        positions: SYSSettingsKey<[String: Int]>,
        totals: SYSSettingsKey<[String: Int]>,
        seeds: SYSSettingsKey<[String: Int]>,
        recent: SYSSettingsKey<[Int]>
    ) {
        self.positions = positions
        self.totals = totals
        self.seeds = seeds
        self.recent = recent
    }
}

#if canImport(Combine)
@MainActor
/// Where a learner is in each lesson (a pack of cards, a chapter, a level), so every flow agrees: - Opening a lesson sta...
public final class SYSLessonProgress: ObservableObject {
    public struct Continuation: Equatable, Sendable {
        public let id: Int
        public let index: Int
        public let total: Int
    }

    @Published public private(set) var recentIDs: [Int]
    @Published public private(set) var continuation: Continuation?

    private let keys: SYSLessonProgressKeys
    private let settings: SYSSettings
    private let recentLimit: Int
    private let debounce: TimeInterval
    private var pending: (id: Int, index: Int, total: Int)?
    private var saveTask: Task<Void, Never>?
    private var closed: Set<Int> = []

    public init(
        keys: SYSLessonProgressKeys,
        settings: SYSSettings = .shared,
        recentLimit: Int = 5,
        debounce: TimeInterval = SYSTiming.standard
    ) {
        self.keys = keys
        self.settings = settings
        self.recentLimit = recentLimit
        self.debounce = debounce
        self.recentIDs = settings[keys.recent]
        self.continuation = nil
        self.continuation = resolveContinuation()
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        #endif
    }

    func hasProgress(for id: Int) -> Bool {
        position(for: id) > 0
    }

    @discardableResult
    public func begin(_ id: Int, total: Int, fresh: Bool) -> (index: Int, seed: SYSShuffleSeed) {
        flush()
        closed.remove(id)

        let saved = position(for: id)
        let index = fresh || saved >= total ? 0 : saved
        let seed = fresh ? SYSShuffleSeed.random() : storedSeed(for: id) ?? .random()

        write(id: id, index: index, total: total)
        store(seed: seed, for: id)
        remember(id)
        continuation = resolveContinuation()
        return (index, seed)
    }

    @discardableResult
    public func reshuffle(_ id: Int, total: Int) -> SYSShuffleSeed {
        begin(id, total: total, fresh: true).seed
    }

    public func record(_ id: Int, index: Int, total: Int) {
        guard !closed.contains(id) else { return }
        if continuation?.id == id {
            continuation = Continuation(id: id, index: index, total: total)
        }
        pending = (id, index, total)
        saveTask?.cancel()
        saveTask = Task { [weak self, debounce] in
            await SYSTiming.pause(debounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    public func finish(_ id: Int) {
        if pending?.id == id {
            pending = nil
            saveTask?.cancel()
        }
        closed.insert(id)

        var positions = settings[keys.positions]
        positions.removeValue(forKey: String(id))
        settings[keys.positions] = positions
        var seeds = settings[keys.seeds]
        seeds.removeValue(forKey: String(id))
        settings[keys.seeds] = seeds

        continuation = resolveContinuation()
    }

    public func flush() {
        saveTask?.cancel()
        guard let save = pending else { return }
        pending = nil
        write(id: save.id, index: save.index, total: save.total)
        continuation = resolveContinuation()
    }

    private func position(for id: Int) -> Int {
        if let pending, pending.id == id { return pending.index }
        return settings[keys.positions][String(id)] ?? 0
    }

    private func storedSeed(for id: Int) -> SYSShuffleSeed? {
        settings[keys.seeds][String(id)].map { SYSShuffleSeed(UInt64(bitPattern: Int64($0))) }
    }

    private func store(seed: SYSShuffleSeed, for id: Int) {
        var seeds = settings[keys.seeds]
        seeds[String(id)] = Int(Int64(bitPattern: seed.value))
        settings[keys.seeds] = seeds
    }

    private func write(id: Int, index: Int, total: Int) {
        var positions = settings[keys.positions]
        positions[String(id)] = index
        settings[keys.positions] = positions
        var totals = settings[keys.totals]
        totals[String(id)] = total
        settings[keys.totals] = totals
    }

    private func remember(_ id: Int) {
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentIDs = Array(ids.prefix(recentLimit))
        settings[keys.recent] = recentIDs
    }

    private func resolveContinuation() -> Continuation? {
        let positions = settings[keys.positions]
        let totals = settings[keys.totals]
        for id in recentIDs {
            guard let index = pending?.id == id ? pending?.index : positions[String(id)], index > 0 else { continue }
            let total = pending?.id == id ? pending?.total ?? 0 : totals[String(id)] ?? 0
            return Continuation(id: id, index: index, total: total)
        }
        return nil
    }
}
#endif
