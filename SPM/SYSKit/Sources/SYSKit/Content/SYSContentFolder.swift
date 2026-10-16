import Foundation

/// Where one downloaded item lives on disk, as a value that is safe to read from any thread.
public struct SYSContentFolder: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func file(_ name: String) -> URL? {
        let candidate = url.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    public func filenames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    public func decode<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
