#if os(iOS)
import SwiftUI

@MainActor
private enum SYSEntranceMemory {
    static var seen: Set<AnyHashable> = []
}

private struct SYSEntrance: ViewModifier {
    private static let staggerLimit = 10

    let order: Int
    let slide: Bool

    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let memoryID: AnyHashable?

    init(order: Int, slide: Bool, memoryID: AnyHashable?) {
        self.order = order
        self.slide = slide
        self.memoryID = memoryID
        _shown = State(initialValue: memoryID.map { SYSEntranceMemory.seen.contains($0) } ?? false)
    }

    private var isStaggered: Bool { order < Self.staggerLimit }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || !slide || !isStaggered || reduceMotion ? 0 : SYSSpace.lg)
            .onAppear {
                guard !shown else { return }
                if let memoryID { SYSEntranceMemory.seen.insert(memoryID) }
                let animation = reduceMotion
                    ? Animation.easeOut(duration: SYSTiming.quick)
                    : SYSMotion.standard.delay(isStaggered ? SYSTiming.stagger(order) : 0)
                withAnimation(animation) { shown = true }
            }
    }
}

public extension View {
    /// Fades and lifts a view in when it first appears, staggered by order; with an id, a view shown once appears at once next time.
    func sysEntrance(_ order: Int = 0, slide: Bool = true, id: AnyHashable? = nil) -> some View {
        modifier(SYSEntrance(order: order, slide: slide, memoryID: id))
    }
}
#endif
