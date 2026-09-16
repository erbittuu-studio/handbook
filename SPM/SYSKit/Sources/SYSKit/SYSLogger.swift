import Foundation
#if canImport(os)
import os
#endif

/// Logging that stays quiet in release and reports real failures.
///
/// `error(_:_:)` is the one that matters: errors otherwise get `print`ed and
/// vanish, so production failures that never crash the app are invisible.
/// Attach a reporter (SYSFirebase provides a Crashlytics one) and they
/// become non-fatals you can actually see.
public enum SYSLogger {
    public enum Level: Int, Comparable {
        case debug = 0, info, warning, error
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Anything below this is dropped. Defaults to `.debug` in DEBUG builds and
    /// `.warning` in release, so shipping builds stay quiet without any setup.
    public static var minimumLevel: Level = {
        #if DEBUG
        return .debug
        #else
        return .warning
        #endif
    }()

    /// Receives non-fatal errors. Set once at launch; nil means log-only.
    public static var reporter: SYSErrorReporter?

    #if canImport(os)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "SYSKit")
    #endif

    public static func debug(_ message: @autoclosure () -> String) { emit(.debug, message()) }
    public static func info(_ message: @autoclosure () -> String) { emit(.info, message()) }
    public static func warning(_ message: @autoclosure () -> String) { emit(.warning, message()) }

    /// Logs, and reports as a non-fatal so it is visible in production.
    public static func error(_ message: @autoclosure () -> String, _ error: Error? = nil) {
        let text = message()
        emit(.error, error.map { "\(text): \($0)" } ?? text)
        reporter?.report(message: text, error: error)
    }

    /// Breadcrumb — shows what the user was doing before a crash.
    public static func breadcrumb(_ message: String) {
        reporter?.breadcrumb(message)
        emit(.debug, message)
    }

    /// A named value attached to every report from here on, until the same key
    /// is set again.
    ///
    /// Distinct from `breadcrumb`: a breadcrumb is one line in a scrolling log,
    /// read in order and easy to miss among a hundred others. A key is a column
    /// — filterable, visible at a glance on every report without opening it.
    /// "Which screen was the user on" is the first question asked of a crash,
    /// and a log entry from three actions ago is not where that answer belongs.
    ///
    /// `nil` is not a way to unset the key — Crashlytics has no such operation,
    /// only overwrite — it is recorded as an empty value, same as `itemId ??
    /// ""` was written by hand before this existed.
    public static func setContext(_ value: String?, for key: String) {
        reporter?.setContext(value, for: key)
    }

    private static func emit(_ level: Level, _ message: String) {
        guard level >= minimumLevel else { return }
        // os.Logger is Apple-only. Falling back to print keeps SYSKit buildable
        // and testable on Linux, which is what lets its tests run on a cheap CI
        // runner instead of a macOS one.
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

/// Implemented by SYSFirebase. Kept as a protocol so SYSKit core needs no
/// Firebase and can be tested without it.
public protocol SYSErrorReporter: AnyObject {
    func report(message: String, error: Error?)
    func breadcrumb(_ message: String)
    /// Implementations record `nil` as an empty value — there is no operation
    /// to remove a key once set.
    func setContext(_ value: String?, for key: String)
}
