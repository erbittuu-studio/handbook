import Foundation

public struct SYSLaunchBlockerText: Equatable, Sendable {
    public var maintenanceTitle: String
    public var maintenanceMessage: String
    public var updateTitle: String
    public var updateMessage: String
    public var offlineTitle: String
    public var offlineMessage: String
    public var retry: String
    public var update: String

    public init(
        appName: String,
        maintenanceTitle: String = "Back Soon",
        maintenanceMessage: String? = nil,
        updateTitle: String = "Time to Update",
        updateMessage: String? = nil,
        offlineTitle: String = "No Connection",
        offlineMessage: String? = nil,
        retry: String = "Try Again",
        update: String = "Update"
    ) {
        self.maintenanceTitle = maintenanceTitle
        self.maintenanceMessage = maintenanceMessage
            ?? "\(appName) is having a quick tidy-up. Please try again in a little while."
        self.updateTitle = updateTitle
        self.updateMessage = updateMessage ?? "A newer version of \(appName) is needed to keep going."
        self.offlineTitle = offlineTitle
        self.offlineMessage = offlineMessage
            ?? "We need the internet to set up \(appName) for the first time."
        self.retry = retry
        self.update = update
    }
}

public struct SYSLaunchBlockerContent: Equatable, Sendable {
    public var symbol: String
    public var title: String
    public var message: String

    public init?(state: SYSAppState, text: SYSLaunchBlockerText) {
        switch state {
        case let .maintenance(message):
            self.init(symbol: "wrench.and.screwdriver.fill", title: text.maintenanceTitle, message: message ?? text.maintenanceMessage)
        case let .updateRequired(message, _):
            self.init(symbol: "arrow.down.circle.fill", title: text.updateTitle, message: message ?? text.updateMessage)
        case .dataUnavailable:
            self.init(symbol: "wifi.exclamationmark", title: text.offlineTitle, message: text.offlineMessage)
        case .onboarding, .whatsNew, .ready:
            return nil
        }
    }

    private init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }
}

public extension SYSAppState {
    var isBlocking: Bool {
        switch self {
        case .maintenance, .updateRequired, .dataUnavailable: return true
        case .onboarding, .whatsNew, .ready: return false
        }
    }
}

#if os(iOS)
import SwiftUI

public struct SYSLaunchBlockerStyle {
    public var background: Color
    public var tint: Color
    public var accent: Color
    public var title: Color
    public var message: Color
    public var titleFont: Font
    public var messageFont: Font
    public var buttonFont: Font

    public init(
        background: Color,
        tint: Color,
        accent: Color,
        title: Color = .primary,
        message: Color = .secondary,
        titleFont: Font = .system(.title, design: .rounded).weight(.bold),
        messageFont: Font = .system(.body, design: .rounded),
        buttonFont: Font = .system(.title3, design: .rounded).weight(.semibold)
    ) {
        self.background = background
        self.tint = tint
        self.accent = accent
        self.title = title
        self.message = message
        self.titleFont = titleFont
        self.messageFont = messageFont
        self.buttonFont = buttonFont
    }
}

public struct SYSLaunchBlocker: View {
    private let content: SYSLaunchBlockerContent?
    private let action: SYSStateAction
    private let style: SYSLaunchBlockerStyle
    private let text: SYSLaunchBlockerText

    @Environment(\.sysMetrics) private var metrics
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badge: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 52
    @State private var bounce = false

    public init(state: SYSAppState, action: SYSStateAction, style: SYSLaunchBlockerStyle, text: SYSLaunchBlockerText) {
        self.content = SYSLaunchBlockerContent(state: state, text: text)
        self.action = action
        self.style = style
        self.text = text
    }

    public var body: some View {
        if let content {
            screen(content)
        }
    }

    private func screen(_ content: SYSLaunchBlockerContent) -> some View {
        ZStack {
            style.background.ignoresSafeArea()

            Circle()
                .fill(style.tint)
                .frame(width: metrics.shortSide * 0.7)
                .blur(radius: 60)
                .offset(x: metrics.shortSide * 0.25, y: -metrics.shortSide * 0.4)
                .allowsHitTesting(false)

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        symbol(content.symbol)

                        VStack(spacing: 8) {
                            Text(content.title)
                                .font(style.titleFont)
                                .foregroundColor(style.title)
                            Text(content.message)
                                .font(style.messageFont)
                                .foregroundColor(style.message)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 32)

                        actionButton
                    }
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        ZStack {
            Circle()
                .fill(style.tint)
                .frame(width: badge, height: badge)
            Image(systemName: name)
                .font(.system(.largeTitle).weight(.semibold))
                .foregroundColor(style.accent)
                .offset(y: bounce ? -4 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bounce)
        }
        .onAppear { bounce = !reduceMotion }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch action {
        case .none:
            EmptyView()
        case let .retry(retry):
            button(text.retry, symbol: "arrow.clockwise", action: retry)
        case let .update(url):
            button(text.update, symbol: "arrow.up.circle.fill") { openURL(url) }
        }
    }

    private func button(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(label)
            }
            .font(style.buttonFont)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(style.accent)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 420)
        .padding(.horizontal, 32)
    }
}

@MainActor
public extension SYSBootstrappedApp {
    func blocker(for state: SYSAppState, style: SYSLaunchBlockerStyle, text: SYSLaunchBlockerText) -> some View {
        SYSLaunchBlocker(state: state, action: action(for: state), style: style, text: text)
    }
}
#endif
