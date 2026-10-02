#if os(iOS)
import SwiftUI

public extension View {
    func sysGlassCard(
        cornerRadius: CGFloat = SYSRadius.xl,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(SYSGlassSurface(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive
        ))
    }

    func sysGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SYSGlassSurface(shape: Capsule(), tint: tint, interactive: interactive))
    }

    func sysGlassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SYSGlassSurface(shape: Circle(), tint: tint, interactive: interactive))
    }
}

private struct SYSGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill((tint ?? .clear).opacity(0.14)))
                .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var value = Glass.regular
        if let tint { value = value.tint(tint.opacity(0.18)) }
        if interactive { value = value.interactive() }
        return value
    }
}

public extension View {
    /// A capsule button in Liquid Glass on iOS 26, a material capsule before; prominent is the one primary action on a screen.
    @ViewBuilder
    func sysGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent).tint(tint)
            } else {
                buttonStyle(.glass).tint(tint)
            }
        } else {
            buttonStyle(SYSGlassFallbackButtonStyle(prominent: prominent, tint: tint))
        }
    }

    /// Fades scrolling content out softly at the edges where floating controls sit, on iOS 26; no change before.
    @ViewBuilder
    func sysScrollEdge(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }
}

private struct SYSGlassFallbackButtonStyle: ButtonStyle {
    let prominent: Bool
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let accent = tint ?? .accentColor
        configuration.label
            .padding(.horizontal, SYSSpace.xl)
            .padding(.vertical, SYSSpace.md)
            .background(Capsule().fill(prominent ? AnyShapeStyle(accent) : AnyShapeStyle(.ultraThinMaterial)))
            .background(Capsule().fill(accent.opacity(prominent ? 0 : 0.14)))
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: SYSStroke.hairline))
            .foregroundStyle(prominent ? Color.white : accent)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(SYSMotion.press, value: configuration.isPressed)
    }
}

public extension View {
    @ViewBuilder
    func sysNumericTransition() -> some View {
        if #available(iOS 17.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    @ViewBuilder
    func sysSymbolBounce<V: Equatable>(value: V) -> some View {
        if #available(iOS 17.0, *) {
            symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }
}
#endif
