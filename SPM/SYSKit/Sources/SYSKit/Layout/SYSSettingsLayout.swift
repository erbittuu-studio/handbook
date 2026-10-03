#if os(iOS)
import SwiftUI

public struct SYSSettingsStyle: Sendable {
    public var sectionTitle: Color
    public var card: Color
    var stroke: Color
    public var title: Color
    public var subtitle: Color
    var chevron: Color
    var onTint: Color
    var rateTint: Color
    var shareTint: Color
    var contactTint: Color

    public init(
        sectionTitle: Color = .secondary,
        card: Color = Color(.secondarySystemGroupedBackground),
        stroke: Color = Color(.separator),
        title: Color = .primary,
        subtitle: Color = .secondary,
        chevron: Color = Color(.tertiaryLabel),
        onTint: Color = .white,
        rateTint: Color = .yellow,
        shareTint: Color = .blue,
        contactTint: Color = .gray
    ) {
        self.sectionTitle = sectionTitle
        self.card = card
        self.stroke = stroke
        self.title = title
        self.subtitle = subtitle
        self.chevron = chevron
        self.onTint = onTint
        self.rateTint = rateTint
        self.shareTint = shareTint
        self.contactTint = contactTint
    }
}

private struct SYSSettingsStyleKey: EnvironmentKey {
    static let defaultValue = SYSSettingsStyle()
}

public extension EnvironmentValues {
    var sysSettingsStyle: SYSSettingsStyle {
        get { self[SYSSettingsStyleKey.self] }
        set { self[SYSSettingsStyleKey.self] = newValue }
    }
}

public extension View {
    func sysSettingsStyle(_ style: SYSSettingsStyle) -> some View {
        environment(\.sysSettingsStyle, style)
    }
}

public struct SYSSettingsSection<Content: View>: View {
    @Environment(\.sysSettingsStyle) private var style
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SYSSpace.sm) {
            Text(title)
                .font(SYSFont.callout.weight(.medium))
                .foregroundColor(style.sectionTitle)
                .padding(.horizontal, SYSSpace.lg)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) { content }
                .padding(.bottom, -SYSStroke.hairline)
                .background(style.card)
                .clipShape(RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SYSRadius.lg, style: .continuous)
                        .stroke(style.stroke, lineWidth: SYSStroke.hairline)
                )
        }
    }
}

public struct SYSSettingsRow<Trailing: View>: View {
    @Environment(\.sysSettingsStyle) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = SYSSize.settingsTile
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = SYSSize.settingsRow

    private let icon: String?
    private let iconURL: URL?
    private let tint: Color
    private let title: String
    private let subtitle: String?
    private let chevron: String?
    private let action: (() -> Void)?
    private let trailing: Trailing

    public init(
        icon: String?,
        iconURL: URL? = nil,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        chevron: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconURL = iconURL
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.chevron = chevron
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(SYSSettingsRowPressStyle(pressed: style.stroke))
            } else {
                row
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.stroke)
                .frame(height: SYSStroke.hairline)
                .padding(.leading, SYSSpace.md + tile + SYSSpace.md)
        }
    }

    private var row: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stackedRow
            } else {
                inlineRow
            }
        }
        .padding(.horizontal, SYSSpace.md)
        .padding(.vertical, SYSSpace.sm)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: SYSSpace.xs / 2) {
            Text(title)
                .font(SYSFont.title3)
                .foregroundColor(style.title)
            if let subtitle {
                Text(subtitle)
                    .font(SYSFont.callout)
                    .foregroundColor(style.subtitle)
            }
        }
    }

    @ViewBuilder
    private var chevronView: some View {
        if Trailing.self == EmptyView.self, action != nil {
            Image(systemName: chevron ?? SYSSymbol.chevronForward)
                .font(SYSFont.rounded.subheadline.weight(.bold))
                .foregroundColor(style.chevron)
        }
    }

    private var inlineRow: some View {
        HStack(spacing: SYSSpace.md) {
            iconTile
            texts
            Spacer(minLength: SYSSpace.sm)
            trailing
            chevronView
        }
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: SYSSpace.sm) {
            HStack(spacing: SYSSpace.md) {
                iconTile
                texts
                Spacer(minLength: SYSSpace.sm)
                chevronView
            }
            trailing
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SYSRadius.sm, style: .continuous).fill(tint)
            if let iconURL {
                AsyncImage(url: iconURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(RoundedRectangle(cornerRadius: SYSRadius.sm, style: .continuous))
            } else if let icon {
                Image(systemName: icon)
                    .font(SYSFont.callout.weight(.medium))
                    .foregroundColor(style.onTint)
            }
        }
        .frame(width: tile, height: tile)
        .accessibilityHidden(true)
    }
}

public extension SYSSettingsRow where Trailing == EmptyView {
    init(
        icon: String?,
        iconURL: URL? = nil,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        chevron: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            iconURL: iconURL,
            tint: tint,
            title: title,
            subtitle: subtitle,
            chevron: chevron,
            action: action
        ) { EmptyView() }
    }
}

private struct SYSSettingsRowPressStyle: ButtonStyle {
    let pressed: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressed : Color.clear)
    }
}

public struct SYSVersionFooter: View {
    @Environment(\.sysSettingsStyle) private var style
    private let credit = SYSAbout.credit

    public init() {}

    public var body: some View {
        VStack(spacing: SYSSpace.xs) {
            HStack(spacing: SYSSpace.xs) {
                Text(SYSAbout.appName())
                    .font(SYSFont.subheadline.weight(.medium))
                    .foregroundColor(style.title)
                Text(SYSVersion.display())
                    .font(SYSFont.footnote)
                    .foregroundColor(style.subtitle)
            }
            Text(credit)
                .font(SYSFont.footnote)
                .foregroundColor(style.subtitle.opacity(SYSOpacity.intense))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, SYSSpace.xl)
        .accessibilityElement(children: .combine)
    }
}
#endif
