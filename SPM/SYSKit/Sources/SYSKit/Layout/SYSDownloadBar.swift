#if os(iOS)
import SwiftUI

private struct SYSDownloadBar: ViewModifier {
    let tint: Color
    @ObservedObject private var readiness = SYSContentReadiness.shared
    @ObservedObject private var connectivity = SYSConnectivity.shared
    @State private var finishing = false
    @State private var lastMissing = 0

    private var total: Int { readiness.fetchTotal }
    private var done: Int { max(total - readiness.fetchMissing, 0) }
    private var fraction: CGFloat { total > 0 ? CGFloat(done) / CGFloat(total) : 0 }
    private var paused: Bool {
        !(readiness.needsUnmetered ? connectivity.allowsOptionalDownloads : connectivity.isOnline)
    }
    private var visible: Bool { total > 0 && (readiness.fetchMissing > 0 || finishing) }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if visible {
                    bar
                        .padding(.horizontal, SYSSpace.lg)
                        .padding(.top, SYSSpace.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(SYSMotion.standard, value: visible)
            .onAppear { lastMissing = readiness.fetchMissing }
            .sysOnChange(of: readiness.fetchMissing) { missing in
                defer { lastMissing = missing }
                guard missing == 0, lastMissing > 0 else { return }
                finishing = true
                SYSTiming.after(1.5) { finishing = false }
            }
    }

    private var bar: some View {
        let muted = paused && !finishing
        return HStack(spacing: SYSSpace.sm) {
            Image(systemName: finishing ? "checkmark.circle.fill" : (paused ? "pause.circle.fill" : "arrow.down.circle.fill"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(muted ? .secondary : tint)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(SYSOpacity.light))
                GeometryReader { proxy in
                    Capsule()
                        .fill(muted ? Color.secondary : tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("\(done)/\(total)")
                .font(SYSFont.caption.weight(.semibold).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, SYSSpace.md)
        .padding(.vertical, SYSSpace.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(SYSOpacity.subtle), lineWidth: SYSStroke.thin))
        .animation(SYSMotion.standard, value: done)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) / \(total)")
    }
}

public extension View {
    /// A slim progress bar below the title bar while the app is still fetching its content by itself: a count such as
    /// 3/12, in the app's own colour, grey while it waits for a connection or Wi-Fi, a check when it finishes, and gone
    /// when nothing is missing. No words, so nothing to translate; it never takes a touch.
    /// `sysDashboardPrompts` attaches it, so a dashboard needs nothing more.
    func sysDownloadBar(tint: Color = .accentColor) -> some View {
        modifier(SYSDownloadBar(tint: tint))
    }
}
#endif
