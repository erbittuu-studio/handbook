#if os(iOS)
import SwiftUI

/// One screen of the first-run flow: a short title, one line, and a live demo the person does something with.
/// The demo gets a binding it sets to true once the person has done the thing; the Next button appears then.
public struct SYSOnboardingStep: Identifiable {
    public let id: String
    public let title: LocalizedStringKey
    public let message: LocalizedStringKey
    let demo: (Binding<Bool>) -> AnyView

    public init<Demo: View>(
        id: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder demo: @escaping (_ done: Binding<Bool>) -> Demo
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.demo = { AnyView(demo($0)) }
    }
}

private struct SYSOnboardingAutoKey: EnvironmentKey {
    static let defaultValue = 0
}

public extension EnvironmentValues {
    /// Goes up by one when a first-run screen has waited five seconds without being tried. A demo plays its own action then,
    /// so the screen never looks stuck.
    var sysOnboardingAuto: Int {
        get { self[SYSOnboardingAutoKey.self] }
        set { self[SYSOnboardingAutoKey.self] = newValue }
    }
}

/// How the flow is drawn: colors and fonts, so each app keeps its own look while the layout and behavior stay shared.
public struct SYSOnboardingStyle {
    public var background: AnyShapeStyle
    public var accent: Color
    public var stage: Color
    public var stageEdge: Color?
    public var title: Font
    public var titleColor: Color
    public var message: Font
    public var messageColor: Color
    public var button: Font

    public init(
        background: AnyShapeStyle = AnyShapeStyle(Color(.systemBackground)),
        accent: Color = .accentColor,
        stage: Color = Color(.secondarySystemGroupedBackground),
        stageEdge: Color? = nil,
        title: Font = SYSFont.rounded.title.weight(.bold),
        titleColor: Color = .primary,
        message: Font = SYSFont.rounded.body,
        messageColor: Color = .secondary,
        button: Font = SYSFont.rounded.title3.weight(.semibold)
    ) {
        self.background = background
        self.accent = accent
        self.stage = stage
        self.stageEdge = stageEdge
        self.title = title
        self.titleColor = titleColor
        self.message = message
        self.messageColor = messageColor
        self.button = button
    }
}

/// The first-run flow every app shares: a few screens, each a live demo to try, Skip always visible, and
/// optionally a last screen of the app's own (a theme or language choice) that ends the flow.
/// Next appears once the demo is done; with VoiceOver on it is always there, so no gesture is required.
public struct SYSOnboardingFlow<Closing: View>: View {
    @Environment(\.sysMetrics) private var metrics
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [SYSOnboardingStep]
    private let style: SYSOnboardingStyle
    private let text: SYSOnboardingText
    private let closing: ((@escaping () -> Void) -> Closing)?
    private let onFinish: () -> Void

    @State private var index = 0
    @State private var finished: Set<String> = []
    @State private var auto: [String: Int] = [:]

    public init(
        steps: [SYSOnboardingStep],
        style: SYSOnboardingStyle,
        text: SYSOnboardingText,
        closing: @escaping (_ finish: @escaping () -> Void) -> Closing,
        onFinish: @escaping () -> Void
    ) {
        self.steps = steps
        self.style = style
        self.text = text
        self.closing = closing
        self.onFinish = onFinish
    }

    private var pageCount: Int { steps.count + (closing == nil ? 0 : 1) }
    private var onClosing: Bool { closing != nil && index == steps.count }

    public var body: some View {
        ZStack {
            Rectangle().fill(style.background).ignoresSafeArea()
            if let closing, onClosing {
                closing(onFinish)
                    .transition(pageTransition)
            } else if steps.indices.contains(index) {
                page(steps[index])
                    .onAppear { playIfIdle(steps[index].id) }
                    .id(steps[index].id)
                    .transition(pageTransition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: SYSTiming.standard) : SYSMotion.pageTurn, value: index)
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func page(_ step: SYSOnboardingStep) -> some View {
        let isDone = finished.contains(step.id)
        let done = Binding(
            get: { finished.contains(step.id) },
            set: { if $0 { finished.insert(step.id) } }
        )

        return VStack(spacing: SYSSpace.lg) {
            topBar
            if metrics.prefersSideBySide {
                HStack(spacing: SYSSpace.xxl) {
                    stage(step, isDone: isDone, done: done)
                        .frame(maxWidth: .infinity, maxHeight: min(metrics.contentSize.height * 0.8, SYSReadableWidth.content))
                    VStack(spacing: SYSSpace.xl) {
                        words(step)
                        advanceButton(isDone: isDone)
                    }
                    .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                stage(step, isDone: isDone, done: done)
                    .frame(maxHeight: min(metrics.contentSize.width, SYSReadableWidth.content) * 0.95)
                words(step)
                advanceButton(isDone: isDone)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: metrics.prefersSideBySide ? 1280 : SYSReadableWidth.content)
        .padding(.horizontal, metrics.screenMargin)
        .padding(.vertical, SYSSpace.lg)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: SYSSpace.xs + 2) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Capsule()
                        .fill(style.titleColor.opacity(page <= index ? 0.9 : SYSOpacity.medium))
                        .frame(width: page == index ? SYSSpace.xl : SYSSpace.sm, height: SYSSpace.sm)
                }
            }
            .animation(SYSMotion.standard, value: index)
            .accessibilityHidden(true)
            Spacer()
            if !onClosing, let skipText = text.skip {
                Button(skipText, action: skip)
                    .font(SYSFont.rounded.body.weight(.medium))
                    .foregroundColor(style.messageColor)
                    .frame(minWidth: SYSSize.touch, minHeight: SYSSize.touch)
            }
        }
    }

    private func stage(_ step: SYSOnboardingStep, isDone: Bool, done: Binding<Bool>) -> some View {
        let shape = RoundedRectangle(cornerRadius: SYSRadius.xl + SYSRadius.md, style: .continuous)
        return step.demo(done)
            .environment(\.sysOnboardingAuto, auto[step.id, default: 0])
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(style.stage))
            .overlay { if let edge = style.stageEdge { shape.stroke(edge, lineWidth: SYSStroke.thin) } }
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: SYSSymbol.doneCircle)
                        .font(SYSFont.rounded.title)
                        .foregroundColor(style.accent)
                        .padding(SYSSpace.lg)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .accessibilityLabel(text.done)
                }
            }
            .clipShape(shape)
            .animation(SYSMotion.bounce, value: isDone)
            .sysSuccessFeedback(trigger: isDone)
            .accessibilityElement(children: .contain)
    }

    private func words(_ step: SYSOnboardingStep) -> some View {
        VStack(spacing: SYSSpace.sm) {
            Text(step.title)
                .font(style.title)
                .foregroundColor(style.titleColor)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Text(step.message)
                .font(style.message)
                .foregroundColor(style.messageColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func advanceButton(isDone: Bool) -> some View {
        let shown = isDone || voiceOver
        let lastStep = closing == nil && index == steps.count - 1
        return Button(action: advance) {
            Text(verbatim: lastStep ? text.start : text.next)
                .font(style.button)
                .frame(maxWidth: .infinity, minHeight: SYSSize.touch)
        }
        .sysGlassButton(prominent: true, tint: style.accent)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : SYSSpace.lg)
        .disabled(!shown)
        .accessibilityHidden(!shown)
        .animation(SYSMotion.bounce, value: shown)
    }

    private func playIfIdle(_ id: String) {
        SYSTiming.after(5) {
            guard steps.indices.contains(index), steps[index].id == id, !finished.contains(id) else { return }
            auto[id, default: 0] += 1
        }
    }

    private func advance() {
        SYSHaptics.selection()
        if index + 1 < pageCount { index += 1 } else { onFinish() }
    }

    private func skip() {
        if closing != nil { index = steps.count } else { onFinish() }
    }
}

public extension SYSOnboardingFlow where Closing == EmptyView {
    init(
        steps: [SYSOnboardingStep],
        style: SYSOnboardingStyle,
        text: SYSOnboardingText,
        onFinish: @escaping () -> Void
    ) {
        self.steps = steps
        self.style = style
        self.text = text
        self.closing = nil
        self.onFinish = onFinish
    }
}
#endif
