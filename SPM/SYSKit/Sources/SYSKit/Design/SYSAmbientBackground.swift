#if os(iOS)
import SwiftUI

/// The two colors a page is drawn from: the app sets them once at its root and every SYSKit screen reads them.
public struct SYSPageTheme: Equatable, Sendable {
    public let base: Color
    public let accent: Color
    let secondary: Color
    let tertiary: Color

    public init(base: Color, accent: Color, secondary: Color? = nil, tertiary: Color? = nil) {
        self.base = base
        self.accent = accent
        self.secondary = secondary ?? accent.shifted(hue: -0.07)
        self.tertiary = tertiary ?? accent.shifted(hue: 0.07)
    }

    static let standard = SYSPageTheme(base: Color(uiColor: .systemBackground), accent: .accentColor)
}

private struct SYSPageThemeKey: EnvironmentKey {
    static let defaultValue = SYSPageTheme.standard
}

public extension EnvironmentValues {
    /// The page theme set at the app root; SYSKit screens read their base color and accent from it.
    var sysPageTheme: SYSPageTheme {
        get { self[SYSPageThemeKey.self] }
        set { self[SYSPageThemeKey.self] = newValue }
    }
}

public extension View {
    /// Sets the page theme for everything below, with optional second and third colors for the backdrop mesh; call it once at the app root with the current theme so a theme change repaints every screen.
    func sysTheme(base: Color, accent: Color, secondary: Color? = nil, tertiary: Color? = nil) -> some View {
        environment(\.sysPageTheme, SYSPageTheme(base: base, accent: accent, secondary: secondary, tertiary: tertiary))
    }

    /// Draws the themed backdrop behind this view.
    func sysPageBackground() -> some View {
        background(SYSAmbientBackground())
    }
}

/// A page background: a soft mesh of the theme accent and its neighbouring hues over the base color, so glass controls above it have color to refract.
public struct SYSAmbientBackground: View {
    @Environment(\.sysPageTheme) private var theme

    public init() {}

    public var body: some View {
        backdrop
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backdrop: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(width: 3, height: 3, points: Self.points, colors: colors)
        } else {
            ZStack {
                theme.base
                LinearGradient(
                    colors: [theme.accent.opacity(0.22), theme.accent.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                RadialGradient(
                    colors: [theme.tertiary.opacity(0.18), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 420
                )
            }
        }
    }

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.55, 0], [1, 0],
        [0, 0.45], [0.35, 0.5], [1, 0.55],
        [0, 1], [0.6, 1], [1, 1],
    ]

    @available(iOS 18.0, *)
    private var colors: [Color] {
        let warm = theme.secondary
        let cool = theme.tertiary
        let base = theme.base
        return [
            base.mix(with: warm, by: 0.34), base.mix(with: theme.accent, by: 0.22), base.mix(with: cool, by: 0.30),
            base.mix(with: theme.accent, by: 0.10), base.mix(with: warm, by: 0.06), base.mix(with: cool, by: 0.10),
            base.mix(with: cool, by: 0.04), base.mix(with: theme.accent, by: 0.12), base.mix(with: warm, by: 0.20),
        ]
    }
}

extension Color {
    func shifted(hue offset: CGFloat) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        let moved = (hue + offset).truncatingRemainder(dividingBy: 1)
        return Color(hue: moved < 0 ? moved + 1 : moved, saturation: saturation, brightness: brightness, opacity: alpha)
    }
}
#endif
