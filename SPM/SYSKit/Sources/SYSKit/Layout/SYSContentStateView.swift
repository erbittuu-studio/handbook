#if os(iOS)
import SwiftUI

/// What a screen shows in place of an item that is not on the device yet: a spinner while it is being fetched, or
/// why it cannot be shown and a Try again button. Every app draws it the same way, from the same words.
/// Pass `nil` for `access` while loading. The colors are the app's, the words come from `SYSContentNoticeText`.
public struct SYSContentStateView: View {
    private let access: SYSItemAccess?
    private let text: SYSContentNoticeText
    private let tint: Color
    private let onTint: Color
    private let primary: Color
    private let secondary: Color
    private let retry: () -> Void

    @ScaledMetric(relativeTo: .title) private var badge: CGFloat = 64

    public init(
        access: SYSItemAccess?,
        text: SYSContentNoticeText = .forLanguages(),
        tint: Color = .accentColor,
        onTint: Color = .white,
        primary: Color = .primary,
        secondary: Color = .secondary,
        retry: @escaping () -> Void = {}
    ) {
        self.access = access
        self.text = text
        self.tint = tint
        self.onTint = onTint
        self.primary = primary
        self.secondary = secondary
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: SYSSpace.md) {
            if let access {
                unavailable(access)
            } else {
                loading
            }
        }
        .padding(SYSSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var loading: some View {
        VStack(spacing: SYSSpace.md) {
            ProgressView()
                .tint(tint)
            Text(text.loading)
                .font(SYSFont.subheadline.weight(.medium))
                .foregroundColor(secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func unavailable(_ access: SYSItemAccess) -> some View {
        let needsInternet = access == .needsInternet
        return VStack(spacing: SYSSpace.md) {
            Image(systemName: needsInternet ? SYSSymbol.offline : SYSSymbol.warning)
                .font(SYSFont.title2.weight(.semibold))
                .foregroundColor(onTint)
                .frame(width: badge, height: badge)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)

            Text(needsInternet ? text.needsInternetTitle : text.failedTitle)
                .font(SYSFont.title3.weight(.semibold))
                .foregroundColor(primary)
                .multilineTextAlignment(.center)

            Text(needsInternet ? text.needsInternetMessage : text.failedMessage)
                .font(SYSFont.subheadline)
                .foregroundColor(secondary)
                .multilineTextAlignment(.center)

            Button {
                SYSHaptics.medium()
                retry()
            } label: {
                Text(text.retry)
                    .font(SYSFont.body.weight(.semibold))
                    .foregroundColor(onTint)
                    .padding(.horizontal, SYSSpace.xl)
                    .padding(.vertical, SYSSpace.md)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(SYSPressStyle())
            .padding(.top, SYSSpace.sm)
        }
    }
}
#endif
