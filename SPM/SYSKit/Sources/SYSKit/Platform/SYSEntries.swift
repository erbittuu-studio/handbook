import Foundation

/// Somewhere the app was asked to go, whether from a link, a search result or a Home Screen shortcut: a kind and an optional id.
public struct SYSEntry: Equatable, Sendable {
    public static let actionKind = "action"

    public let kind: String
    public let id: String?

    public init(kind: String, id: String? = nil) {
        self.kind = kind
        self.id = id
    }

    public static func action(_ id: String) -> SYSEntry {
        SYSEntry(kind: actionKind, id: id)
    }
}

@MainActor
/// Gathers every way into the app and hands each one over once the app is ready, so no app writes its own link, search or shortcut plumbing.
public final class SYSEntries {
    public static let shared = SYSEntries()

    private let pending = SYSPendingIntent<SYSEntry>()
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var shortcutPrefix: String {
        "\(bundle.bundleIdentifier ?? "app").quickaction."
    }

    public func receive(_ entry: SYSEntry) {
        pending.receive(entry)
    }

    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let scheme = SYSDeepLink.scheme(bundle: bundle) else { return false }
        return open(url, scheme: scheme)
    }

    @discardableResult
    func open(_ url: URL, scheme: String) -> Bool {
        guard let target = SYSDeepLink.target(of: url, scheme: scheme) else { return false }
        receive(SYSEntry(kind: target.kind, id: target.id))
        return true
    }

    public func markReady(_ deliver: @escaping (SYSEntry) -> Void) {
        pending.markReady(deliver: deliver)
    }
}

#if canImport(CoreSpotlight) && !os(watchOS)
extension SYSEntries {
    public func openSpotlight(_ identifier: String) {
        guard let parsed = SYSSpotlight.parseIdentifier(identifier) else { return }
        receive(SYSEntry(kind: parsed.kind, id: parsed.id))
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
extension SYSEntries {
    public func registerQuickActions(_ actions: [SYSQuickAction]) {
        SYSQuickActions.register(actions.map { action in
            SYSQuickAction(
                id: shortcutPrefix + action.id,
                title: action.title,
                subtitle: action.subtitle,
                systemImageName: action.systemImageName
            )
        })
    }

    @discardableResult
    public func perform(shortcutType: String) -> Bool {
        guard shortcutType.hasPrefix(shortcutPrefix) else { return false }
        receive(.action(String(shortcutType.dropFirst(shortcutPrefix.count))))
        return true
    }
}
#endif
