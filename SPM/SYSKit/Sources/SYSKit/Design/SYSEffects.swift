#if os(iOS)
import SwiftUI

public enum SYSSheetDetent {
    case small
    case medium
    case large
}

public extension View {
    @ViewBuilder
    func sysOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func sysSymbolBreathe(isActive: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.breathe, isActive: isActive)
        } else if #available(iOS 17.0, *) {
            symbolEffect(.pulse.byLayer, isActive: isActive)
        } else {
            self
        }
    }

    @ViewBuilder
    func sysSymbolRotate(isActive: Bool) -> some View {
        if #available(iOS 18.0, *) {
            symbolEffect(.rotate, isActive: isActive)
        } else if #available(iOS 17.0, *) {
            symbolEffect(.variableColor.iterative, isActive: isActive)
        } else {
            self
        }
    }

    @ViewBuilder
    func sysSymbolReplace() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }

    @ViewBuilder
    func sysInterpolateTransition() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.interpolate)
        } else {
            self
        }
    }

    @ViewBuilder
    func sysScrollTransition() -> some View {
        if #available(iOS 17.0, *) {
            scrollTransition(.animated(.smooth)) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.85)
                    .scaleEffect(phase.isIdentity ? 1 : 0.96)
                    .blur(radius: phase.isIdentity ? 0 : 1)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func sysHorizontalScrollTransition() -> some View {
        if #available(iOS 17.0, *) {
            scrollTransition(.animated(.snappy), axis: .horizontal) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.7)
                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func sysSheetDetents(_ detent: SYSSheetDetent) -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents(detent.presentationDetents)
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    func sysReadableWidth(_ width: CGFloat = SYSReadableWidth.content) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }

    func sysShimmer() -> some View {
        modifier(SYSShimmer())
    }
}

@available(iOS 16.0, *)
private extension SYSSheetDetent {
    var presentationDetents: Set<PresentationDetent> {
        switch self {
        case .small: return [.height(280)]
        case .medium: return [.medium]
        case .large: return [.large]
        }
    }
}

private struct SYSShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * phase)
                    }
                    .clipped()
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    /// A selection tap on iOS 17 and later when trigger changes; nothing before.
    @ViewBuilder
    func sysSelectionFeedback<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) { sensoryFeedback(.selection, trigger: trigger) } else { self }
    }

    /// An increase tap on iOS 17 and later when trigger changes; nothing before.
    @ViewBuilder
    func sysIncreaseFeedback<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) { sensoryFeedback(.increase, trigger: trigger) } else { self }
    }

    /// A success tap on iOS 17 and later when trigger changes; nothing before.
    @ViewBuilder
    func sysSuccessFeedback<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *) { sensoryFeedback(.success, trigger: trigger) } else { self }
    }
}
#endif
