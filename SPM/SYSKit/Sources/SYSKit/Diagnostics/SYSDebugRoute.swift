import Foundation

public struct SYSDebugRoute: Equatable, Sendable {
    public let name: String
    public let id: String?

    public init?(_ argument: String) {
        let parts = argument.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first, !name.isEmpty else { return nil }
        self.name = name
        self.id = parts.count > 1 ? parts[1] : nil
    }

    public static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func parse(_ arguments: [String]) -> SYSDebugRoute? {
        value(of: "-debugRoute", in: arguments).flatMap(SYSDebugRoute.init)
    }

    public static var launch: SYSDebugRoute? {
        #if DEBUG
        parse(CommandLine.arguments)
        #else
        nil
        #endif
    }
}

public extension SYSAppState {
    internal static func forced(by arguments: [String]) -> SYSAppState? {
        switch SYSDebugRoute.value(of: "-debugState", in: arguments) {
        case "maintenance": return .maintenance(message: nil)
        case "update": return .updateRequired(message: nil, storeURL: URL(string: "https://apps.apple.com"))
        case "offline": return .dataUnavailable(.offline)
        default: return nil
        }
    }

    internal static var debugForced: SYSAppState? {
        #if DEBUG
        forced(by: CommandLine.arguments)
        #else
        nil
        #endif
    }
}
