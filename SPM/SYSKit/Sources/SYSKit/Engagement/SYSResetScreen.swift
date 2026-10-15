#if os(iOS)
import SwiftUI

/// The words on the reset screen; the app writes them in its own localization so SYSKit carries no strings.
public struct SYSResetText {
    public var title: String
    public var message: String
    public var button: String
    public var hint: String

    public init(title: String, message: String, button: String, hint: String) {
        self.title = title
        self.message = message
        self.button = button
        self.hint = hint
    }
}

/// How the reset screen is drawn: colors and fonts, so each app keeps its own look while the layout and behavior stay shared.
public struct SYSResetStyle {
    public var background: AnyShapeStyle
    public var accent: Color
    public var title: Font
    public var titleColor: Color
    public var message: Font
    public var messageColor: Color
    public var button: Font
    public var buttonColor: Color

    public init(
        background: AnyShapeStyle = AnyShapeStyle(Color(.systemBackground)),
        accent: Color = .red,
        title: Font = SYSFont.rounded.title.weight(.bold),
        titleColor: Color = .primary,
        message: Font = SYSFont.rounded.body,
        messageColor: Color = .secondary,
        button: Font = SYSFont.rounded.title2.weight(.bold),
        buttonColor: Color = .primary
    ) {
        self.background = background
        self.accent = accent
        self.title = title
        self.titleColor = titleColor
        self.message = message
        self.messageColor = messageColor
        self.button = button
        self.buttonColor = buttonColor
    }
}

/// One reset screen for every app: what will be erased, and a round button in the middle that has to be held for three seconds.
/// The ring fills and a countdown counts down while the finger stays down; letting go early cancels, holding to the end calls
/// `onReset`. The container supplies the title. With VoiceOver the same button is an action in the actions rotor.
public struct SYSResetScreen: View {
    private let text: SYSResetText
    private let style: SYSResetStyle
    private let holdSeconds: Double
    private let onReset: () -> Void

    @State private var pressStart: Date?
    @State private var finished = false

    public init(text: SYSResetText, style: SYSResetStyle, holdSeconds: Double = 3, onReset: @escaping () -> Void) {
        self.text = text
        self.style = style
        self.holdSeconds = holdSeconds
        self.onReset = onReset
    }

    public var body: some View {
        ZStack {
            Rectangle().fill(style.background).ignoresSafeArea()
            VStack(spacing: SYSSpace.xxl) {
                Spacer(minLength: 0)
                VStack(spacing: SYSSpace.lg) {
                    Image(systemName: SYSSymbol.replay)
                        .font(SYSFont.largeTitle.weight(.bold))
                        .foregroundColor(style.accent)
                        .accessibilityHidden(true)
                    Text(text.message)
                        .font(style.message)
                        .foregroundColor(style.messageColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                holdButton
                Text(text.hint)
                    .font(style.message)
                    .foregroundColor(style.messageColor)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SYSSpace.xl)
            .sysReadableWidth()
        }
        .sysSuccessFeedback(trigger: finished)
    }

    private var holdButton: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: pressStart == nil)) { context in
            let progress = progress(at: context.date)
            ZStack {
                Circle().stroke(style.accent.opacity(SYSOpacity.light), lineWidth: 14)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: SYSSpace.xs) {
                    Text(text.button)
                        .font(style.button)
                        .foregroundColor(style.buttonColor)
                        .minimumScaleFactor(0.6)
                    if pressStart != nil, !finished {
                        Text(verbatim: "\(remaining(at: progress))")
                            .font(SYSFont.rounded.largeTitle.weight(.heavy))
                            .foregroundColor(style.accent)
                    }
                }
                .padding(SYSSpace.xl)
            }
        }
        .frame(width: 200, height: 200)
        .scaleEffect(pressStart != nil && !finished ? 0.95 : 1)
        .animation(SYSMotion.standard, value: pressStart != nil)
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: holdSeconds,
            maximumDistance: 120,
            perform: complete,
            onPressingChanged: pressing
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.button)
        .accessibilityHint(text.hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(text.button), complete)
    }

    private func progress(at date: Date) -> CGFloat {
        if finished { return 1 }
        guard let start = pressStart else { return 0 }
        return CGFloat(min(1, max(0, date.timeIntervalSince(start) / holdSeconds)))
    }

    private func remaining(at progress: CGFloat) -> Int {
        max(1, Int((Double(1 - progress) * holdSeconds).rounded(.up)))
    }

    private func pressing(_ isPressing: Bool) {
        guard !finished else { return }
        if isPressing {
            SYSHaptics.selection()
            pressStart = Date()
        } else {
            pressStart = nil
        }
    }

    private func complete() {
        guard !finished else { return }
        finished = true
        onReset()
    }
}
#endif
