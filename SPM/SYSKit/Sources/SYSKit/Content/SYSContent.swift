import Foundation

enum SYSContent {
    static func directory(_ fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true)
        let directory = support.appendingPathComponent("Content", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var mutable = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutable.setResourceValues(values)
        }
        return directory
    }

    static func packs(_ fileManager: FileManager = .default) throws -> URL {
        let directory = try self.directory(fileManager).appendingPathComponent("packs",
                                                                               isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func file(_ name: String, _ fileManager: FileManager = .default) throws -> URL {
        try directory(fileManager).appendingPathComponent(name)
    }
}
