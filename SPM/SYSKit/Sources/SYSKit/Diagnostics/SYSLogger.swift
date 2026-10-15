import Foundation
#if canImport(os)
import os
#endif

/// Logging that stays quiet in release.
public enum SYSLogger {
    enum Level: Int, Comparable {
        case debug = 0, info, warning, error
        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static var minimumLevel: Level {
        get { configuration.value.minimumLevel }
        set { configuration.withLock { $0.minimumLevel = newValue } }
    }

    static var sink: ((String) -> Void)? {
        get { configuration.value.sink }
        set { configuration.withLock { $0.sink = newValue } }
    }

    private struct Configuration {
        var minimumLevel: Level = {
            #if DEBUG
            return .debug
            #else
            return .warning
            #endif
        }()
        var sink: ((String) -> Void)?
    }

    private static let configuration = SYSLocked(Configuration())

    #if canImport(os)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "SYSKit")
    #endif

    static func debug(_ message: @autoclosure () -> String) { emit(.debug, message()) }
    public static func info(_ message: @autoclosure () -> String) { emit(.info, message()) }
    public static func warning(_ message: @autoclosure () -> String) { emit(.warning, message()) }

    public static func error(_ message: @autoclosure () -> String, _ error: Error? = nil) {
        let text = message()
        emit(.error, error.map { "\(text): \($0)" } ?? text)
    }

    private static func emit(_ level: Level, _ message: String) {
        guard level >= minimumLevel else { return }
        sink?("[\(level)] \(message)")
        #if canImport(os)
        switch level {
        case .debug: log.debug("\(message, privacy: .public)")
        case .info: log.info("\(message, privacy: .public)")
        case .warning: log.warning("\(message, privacy: .public)")
        case .error: log.error("\(message, privacy: .public)")
        }
        #else
        print("[\(level)] \(message)")
        #endif
    }
}
