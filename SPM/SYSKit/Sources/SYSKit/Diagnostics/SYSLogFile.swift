import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Keeps what SYSLogger says on disk, so a support request can carry the last few sessions.
public final class SYSLogFile: @unchecked Sendable {
    public static let shared = SYSLogFile()

    private let queue = DispatchQueue(label: "sys.logfile", qos: .utility)
    private let maxFileSize: UInt64 = 2 * 1024 * 1024
    private let maxFiles = 3
    private var handle: FileHandle?

    private init() {}

    var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private var currentURL: URL { directory.appendingPathComponent("log.txt") }

    @MainActor static var deviceHeader: String {
        #if canImport(UIKit) && !os(watchOS)
        "Device: \(UIDevice.current.model) | iOS \(UIDevice.current.systemVersion)\nApp: \(SYSVersion.display())\n"
        #else
        "App: \(SYSVersion.display())\n"
        #endif
    }

    @MainActor public func install() {
        install(level: .info, header: Self.deviceHeader)
    }

    @MainActor func install(level: SYSLogger.Level, header: String) {
        queue.sync {
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: currentURL.path) {
                fileManager.createFile(atPath: currentURL.path, contents: nil)
            }
            rotateIfNeeded()
            handle = try? FileHandle(forWritingTo: currentURL)
            _ = try? handle?.seekToEnd()
            write("\n\n" + String(repeating: "=", count: 60) + "\nSESSION START: \(Self.stamp(Date()))\n\(header)"
                  + String(repeating: "=", count: 60) + "\n\n")
        }
        SYSLogger.minimumLevel = min(SYSLogger.minimumLevel, level)
        SYSLogger.sink = { [weak self] line in self?.append(line) }
    }

    func combinedData() -> Data? {
        queue.sync {
            let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "txt" }
                .sorted { $0.path < $1.path }
            var combined = ""
            for url in files.reversed() {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    combined += "=== \(url.lastPathComponent) ===\n\(content)\n\n"
                }
            }
            return combined.data(using: .utf8)
        }
    }

    private func append(_ line: String) {
        queue.async { [self] in
            write("[\(Self.stamp(Date()))] \(line)\n")
            rotateIfNeeded(reopen: true)
        }
    }

    private func write(_ text: String) {
        // write(contentsOf:) throws; the older write(_:) raises an ObjC exception on a closed handle and would crash the app
        if let data = text.data(using: .utf8) { try? handle?.write(contentsOf: data) }
    }

    private func rotateIfNeeded(reopen: Bool = false) {
        let fileManager = FileManager.default
        guard let size = (try? fileManager.attributesOfItem(atPath: currentURL.path))?[.size] as? UInt64,
              size > maxFileSize else { return }

        try? handle?.close()
        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let old = directory.appendingPathComponent("log.\(index).txt")
            let next = directory.appendingPathComponent("log.\(index + 1).txt")
            try? fileManager.removeItem(at: next)
            try? fileManager.moveItem(at: old, to: next)
        }
        try? fileManager.moveItem(at: currentURL, to: directory.appendingPathComponent("log.1.txt"))
        fileManager.createFile(atPath: currentURL.path, contents: nil)
        if reopen {
            handle = try? FileHandle(forWritingTo: currentURL)
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
