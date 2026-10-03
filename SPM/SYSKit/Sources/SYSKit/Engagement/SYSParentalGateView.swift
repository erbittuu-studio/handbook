#if os(iOS)
import SwiftUI

/// The words on the gate; the app writes them in its own localization so SYSKit carries no strings.
public struct SYSParentalGateText {
    public var title: String
    public var watch: String
    public var tapLargest: String
    public var tapSmallest: String
    public var attemptsLeft: (Int) -> String
    public var explanation: String
    public var close: String
    public var numberLabel: (Int) -> String
    public var selectHint: String?
    public var waitHint: String?

    public init(
        title: String,
        watch: String,
        tapLargest: String,
        tapSmallest: String,
        attemptsLeft: @escaping (Int) -> String,
        explanation: String,
        close: String,
        numberLabel: @escaping (Int) -> String = { "\($0)" },
        selectHint: String? = nil,
        waitHint: String? = nil
    ) {
        self.title = title
        self.watch = watch
        self.tapLargest = tapLargest
        self.tapSmallest = tapSmallest
        self.attemptsLeft = attemptsLeft
        self.explanation = explanation
        self.close = close
        self.numberLabel = numberLabel
        self.selectHint = selectHint
        self.waitHint = waitHint
    }
}

/// How the gate is drawn: colors and fonts, so each app and theme keeps its own look while the layout and logic stay shared.
public struct SYSParentalGateStyle {
    public var question: Font
    public var questionColor: Color
    /// The pill behind the question; nil draws the question straight on the backdrop.
    public var plate: Color?
    public var plateEdge: Color?
    public var number: Font
    public var numberColor: Color
    public var tile: (Int) -> Color
    public var tileEdge: Color?
    public var right: Color
    public var wrong: Color
    public var caption: Font
    public var captionColor: Color
    /// Pass .dark when the backdrop is dark so the bar's title and close button stay readable.
    public var barScheme: ColorScheme?

    public init(
        question: Font = SYSFont.rounded.title.weight(.bold),
        questionColor: Color = .primary,
        plate: Color? = nil,
        plateEdge: Color? = nil,
        number: Font = SYSFont.rounded.title.weight(.bold),
        numberColor: Color = .primary,
        tile: @escaping (Int) -> Color = { _ in Color(.secondarySystemGroupedBackground) },
        tileEdge: Color? = nil,
        right: Color = .green,
        wrong: Color = .red,
        caption: Font = SYSFont.callout,
        captionColor: Color = .secondary,
        barScheme: ColorScheme? = nil
    ) {
        self.question = question
        self.questionColor = questionColor
        self.plate = plate
        self.plateEdge = plateEdge
        self.number = number
        self.numberColor = numberColor
        self.tile = tile
        self.tileEdge = tileEdge
        self.right = right
        self.wrong = wrong
        self.caption = caption
        self.captionColor = captionColor
        self.barScheme = barScheme
    }
}

struct SYSParentalGateView<Backdrop: View>: View {
    @ObservedObject var gate: SYSParentalGate
    let text: SYSParentalGateText
    let style: SYSParentalGateStyle
    let backdrop: Backdrop

    @Environment(\.sysMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealed: Set<Int> = []
    @State private var ready = false
    @State private var wrongTile: Int?
    @State private var rightTile: Int?
    @State private var shake: CGFloat = 0
    @State private var locked = false

    var body: some View {
        SYSNavigationContainer(
            title: text.title,
            trailing: .close(text.close) { gate.cancel() }
        ) {
            ZStack {
                backdrop.ignoresSafeArea()

                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        content
                            .padding(SYSSpace.lg)
                            .frame(maxWidth: metrics.prefersSideBySide ? SYSReadableWidth.grid : SYSReadableWidth.form)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height)
                    }
                }
            }
            .modifier(SYSParentalGateBar(scheme: style.barScheme))
        }
        .interactiveDismissDisabled(true)
        .onAppear(perform: begin)
    }

    @ViewBuilder
    private var content: some View {
        if metrics.prefersSideBySide {
            HStack(spacing: SYSSpace.xxl) {
                VStack(spacing: SYSSpace.lg) {
                    question
                    footer
                }
                .frame(maxWidth: .infinity)

                grid
            }
        } else {
            VStack(spacing: SYSSpace.xl) {
                Spacer(minLength: 0)
                question
                grid
                footer
                Spacer(minLength: 0)
            }
        }
    }

    private var questionText: String {
        guard ready else { return text.watch }
        return gate.challenge?.ask == .smallest ? text.tapSmallest : text.tapLargest
    }

    @ViewBuilder
    private var question: some View {
        let label = Text(questionText)
            .font(style.question)
            .foregroundColor(style.questionColor)
            .multilineTextAlignment(.center)

        if let plate = style.plate {
            label
                .padding(.horizontal, SYSSpace.lg)
                .padding(.vertical, SYSSpace.sm)
                .background(Capsule().fill(plate))
                .overlay(Capsule().strokeBorder(style.plateEdge ?? .clear, lineWidth: 3))
        } else {
            label
        }
    }

    private var grid: some View {
        let spacing: CGFloat = metrics.isCompactWidth ? 16 : 20
        let numbers = gate.challenge?.numbers ?? []

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3), spacing: spacing) {
            ForEach(Array(numbers.enumerated()), id: \.element) { index, number in
                tile(number, index: index)
            }
        }
        .frame(maxWidth: min(SYSReadableWidth.form, 420))
    }

    private func tile(_ number: Int, index: Int) -> some View {
        let shown = revealed.contains(number)
        let fill = rightTile == number ? style.right : wrongTile == number ? style.wrong : style.tile(index)

        return ZStack {
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(style.tileEdge ?? .clear, lineWidth: 3))
                .shadow(radius: 5)

            Text("\(number)")
                .font(style.number)
                .foregroundColor(style.numberColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(SYSSpace.sm)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
            .offset(x: wrongTile == number ? shake : 0)
            .scaleEffect(shown ? (rightTile == number ? 1.15 : 1) : 0.3)
            .opacity(shown ? 1 : 0)
            .contentShape(Circle())
            .onTapGesture { tap(number) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.numberLabel(number))
            .accessibilityHint(ready ? (text.selectHint ?? "") : (text.waitHint ?? ""))
            .accessibilityAddTraits(.isButton)
    }

    private var footer: some View {
        VStack(spacing: SYSSpace.sm) {
            Text(text.attemptsLeft(gate.attemptsLeft))
                .font(style.caption.weight(.semibold))
            Text(text.explanation)
                .font(style.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(style.captionColor)
    }

    private func begin() {
        guard let numbers = gate.challenge?.numbers else { return }
        SYSHaptics.rigid()
        revealed = []
        ready = false
        locked = false

        for (index, number) in numbers.enumerated() {
            SYSTiming.after(SYSTiming.stagger(index, step: SYSTiming.standard)) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.6)) {
                    _ = revealed.insert(number)
                }
                SYSHaptics.light()
            }
        }

        SYSTiming.after(SYSTiming.stagger(numbers.count, step: SYSTiming.standard) + SYSTiming.standard) {
            ready = true
        }
    }

    private func tap(_ number: Int) {
        guard ready, !locked else { return }
        locked = true

        if gate.answer(number) {
            SYSHaptics.success()
            withAnimation(.easeOut(duration: SYSTiming.quick)) { rightTile = number }
            return
        }

        SYSHaptics.error()
        wrongTile = number
        let sequence: [CGFloat] = reduceMotion ? [] : [-10, 10, -8, 8, -4, 4, 0]
        for (index, value) in sequence.enumerated() {
            SYSTiming.after(SYSTiming.stagger(index, step: 0.04)) { shake = value }
        }
        SYSTiming.after(SYSTiming.relaxed) {
            wrongTile = nil
            shake = 0
            locked = false
        }
    }
}

private struct SYSParentalGateBar: ViewModifier {
    let scheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(scheme, for: .navigationBar)
        } else {
            content
        }
    }
}

public extension View {
    /// Presents the parental gate over this view whenever `gate.isPresented` is true; the backdrop is whatever the app wants behind the numbers.
    func sysParentalGate<Backdrop: View>(
        _ gate: SYSParentalGate,
        text: SYSParentalGateText,
        style: SYSParentalGateStyle = SYSParentalGateStyle(),
        @ViewBuilder backdrop: () -> Backdrop
    ) -> some View {
        modifier(SYSParentalGatePresenter(gate: gate, text: text, style: style, backdrop: backdrop()))
    }

    /// Presents the parental gate over this view on the page theme's backdrop.
    func sysParentalGate(
        _ gate: SYSParentalGate,
        text: SYSParentalGateText,
        style: SYSParentalGateStyle = SYSParentalGateStyle()
    ) -> some View {
        sysParentalGate(gate, text: text, style: style) { SYSAmbientBackground() }
    }
}

private struct SYSParentalGatePresenter<Backdrop: View>: ViewModifier {
    @ObservedObject var gate: SYSParentalGate
    let text: SYSParentalGateText
    let style: SYSParentalGateStyle
    let backdrop: Backdrop

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $gate.isPresented) {
            SYSParentalGateView(gate: gate, text: text, style: style, backdrop: backdrop)
        }
    }
}
#endif
