import Foundation
import Combine

/// What a gate reports about itself, so the app can send it wherever it sends analytics.
public enum SYSParentalGateEvent: Sendable, Equatable {
    case shown
    case passed
    case failed
}

/// Which number the adult is asked to find.
public enum SYSParentalGateAsk: Sendable, Equatable {
    case largest
    case smallest
}

/// One round of the gate: nine different numbers and which one to tap.
public struct SYSParentalGateChallenge: Sendable, Equatable {
    public let numbers: [Int]
    public let ask: SYSParentalGateAsk

    public init(numbers: [Int], ask: SYSParentalGateAsk) {
        self.numbers = numbers
        self.ask = ask
    }

    /// The number that passes the gate.
    public var answer: Int {
        (ask == .largest ? numbers.max() : numbers.min()) ?? 0
    }

    /// A fresh round with distinct numbers drawn from the range, in random order.
    public static func make<Generator: RandomNumberGenerator>(
        count: Int = 9,
        range: ClosedRange<Int> = 1...100,
        using generator: inout Generator
    ) -> SYSParentalGateChallenge {
        let numbers = Array(range.shuffled(using: &generator).prefix(count))
        let ask: SYSParentalGateAsk = Bool.random(using: &generator) ? .largest : .smallest
        return SYSParentalGateChallenge(numbers: numbers, ask: ask)
    }

    /// A fresh round using the system random number generator.
    public static func make(count: Int = 9, range: ClosedRange<Int> = 1...100) -> SYSParentalGateChallenge {
        var generator = SystemRandomNumberGenerator()
        return make(count: count, range: range, using: &generator)
    }
}

/// The state of a parental gate: ask a question, count wrong answers, and run the guarded action only after a right one.
///
/// Hold one per app (a `@StateObject` at the root), pass it down, and call `trigger` where the guarded action would run. Draw it with `sysParentalGate(_:text:style:)`.
@MainActor
public final class SYSParentalGate: ObservableObject {
    @Published public var isPresented = false
    @Published public private(set) var attemptsLeft: Int
    public private(set) var challenge: SYSParentalGateChallenge?

    public let maxAttempts: Int
    /// Seconds to wait after a right answer before running the guarded action, so the gate finishes dismissing first.
    public var successDelay: TimeInterval
    public var onEvent: ((SYSParentalGateEvent) -> Void)?

    private var onSuccess: (() -> Void)?

    public init(
        maxAttempts: Int = 3,
        successDelay: TimeInterval = 0.8,
        onEvent: ((SYSParentalGateEvent) -> Void)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.attemptsLeft = maxAttempts
        self.successDelay = successDelay
        self.onEvent = onEvent
    }

    /// Opens the gate with a new question; `action` runs only if the adult answers it.
    public func trigger(action: @escaping () -> Void) {
        attemptsLeft = maxAttempts
        challenge = SYSParentalGateChallenge.make()
        onSuccess = action
        isPresented = true
        onEvent?(.shown)
    }

    /// Checks a tapped number; returns true when it passes. Running out of attempts closes the gate.
    @discardableResult
    public func answer(_ value: Int) -> Bool {
        guard let challenge else { return false }

        if value == challenge.answer {
            isPresented = false
            onEvent?(.passed)
            let finish = onSuccess
            onSuccess = nil
            let delay = successDelay
            Task { @MainActor in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                finish?()
            }
            return true
        }

        attemptsLeft -= 1
        if attemptsLeft <= 0 {
            onEvent?(.failed)
            cancel()
        }
        return false
    }

    /// Closes the gate without running the guarded action.
    public func cancel() {
        isPresented = false
        onSuccess = nil
    }
}
