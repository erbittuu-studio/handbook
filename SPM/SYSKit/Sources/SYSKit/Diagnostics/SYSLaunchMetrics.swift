import Foundation
import os

enum SYSLaunchMilestone: String, CaseIterable, Sendable {
    case appLaunched
    case startupBegan
    case contentPrepared
    case ready
    case homeShown
}

final class SYSLaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let now: () -> Date
    private let processStart: Date?
    private var marks: [SYSLaunchMilestone: Date] = [:]

    init(processStart: Date?, now: @escaping () -> Date = Date.init) {
        self.processStart = processStart
        self.now = now
    }

    @discardableResult
    func mark(_ milestone: SYSLaunchMilestone) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard marks[milestone] == nil else { return false }
        marks[milestone] = now()
        return true
    }

    var summary: String? {
        lock.lock()
        defer { lock.unlock() }
        guard let home = marks[.homeShown], let origin = processStart ?? marks[.appLaunched] else { return nil }

        var parts: [(String, Date?, Date?)] = [
            ("process", processStart, marks[.appLaunched]),
            ("startup", marks[.appLaunched], marks[.startupBegan]),
            ("loading", marks[.startupBegan], marks[.contentPrepared]),
            ("splash hold", marks[.contentPrepared], marks[.ready]),
            ("home", marks[.ready], marks[.homeShown])
        ]
        parts.removeAll { $0.1 == nil || $0.2 == nil }
        let detail = parts.compactMap { name, from, to -> String? in
            guard let from, let to else { return nil }
            return "\(name) \(Self.milliseconds(to.timeIntervalSince(from)))"
        }
        let total = Self.milliseconds(home.timeIntervalSince(origin))
        return "launch: \(total) ms to home" + (detail.isEmpty ? "" : " (" + detail.joined(separator: ", ") + ")")
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds * 1000).rounded()))
    }
}

enum SYSLaunchMetrics {
    private static let recorder = SYSLaunchRecorder(processStart: processStartTime())
    private static let signposts = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "SYSKit", category: .pointsOfInterest)

    static func mark(_ milestone: SYSLaunchMilestone) {
        guard recorder.mark(milestone) else { return }
        switch milestone {
        case .appLaunched:
            os_signpost(.begin, log: signposts, name: "Launch")
        case .homeShown:
            os_signpost(.end, log: signposts, name: "Launch")
        default:
            os_signpost(.event, log: signposts, name: "Launch", "%{public}s", milestone.rawValue)
        }
        if milestone == .homeShown, let line = recorder.summary {
            SYSLogger.info(line)
        }
    }

    static var summary: String? { recorder.summary }

    private static func processStartTime() -> Date? {
        #if targetEnvironment(simulator)
        return nil
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&request, UInt32(request.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        #endif
    }
}
