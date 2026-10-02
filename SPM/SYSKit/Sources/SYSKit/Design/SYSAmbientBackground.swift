#if os(iOS)
import SwiftUI

/// The two colors a page is drawn from: the app sets them once at its root and every SYSKit screen reads them.
public struct SYSPageTheme: Equatable, Sendable {
    public let base: Color
    public let accent: Color

    public init(base: Color, accent: Color) {
        self.base = base
        self.accent = accent
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
    /// Sets the page theme for everything below; call it once at the app root with the current theme so a theme change repaints every screen.
    func sysTheme(base: Color, accent: Color) -> some View {
        environment(\.sysPageTheme, SYSPageTheme(base: base, accent: accent))
    }

    /// Draws the themed backdrop behind this view.
    func sysPageBackground() -> some View {
        background(SYSAmbientBackground())
    }
}

/// A page background with a faint accent wash and two soft blurs of the accent color, so glass controls above it have color to refract.
public struct SYSAmbientBackground: View {
    @Environment(\.sysMetrics) private var metrics
    @Environment(\.sysPageTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.base
            LinearGradient(
                colors: [theme.accent.opacity(0.10), theme.accent.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
            Circle()
                .fill(theme.accent.opacity(0.22))
                .frame(width: metrics.shortSide * 0.76)
                .blur(radius: 70)
                .offset(x: metrics.shortSide * 0.3, y: -metrics.shortSide * 0.25)
            Circle()
                .fill(theme.accent.opacity(0.12))
                .frame(width: metrics.shortSide * 0.56)
                .blur(radius: 55)
                .offset(x: -metrics.shortSide * 0.23, y: metrics.shortSide * 0.86)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
