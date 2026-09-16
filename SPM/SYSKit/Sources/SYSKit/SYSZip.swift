import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal ZIP reader: enough to unpack a content bundle SYSContentSync just
/// downloaded, nothing more (no writing, no encryption, no zip64). Built in
/// rather than pulled in as a dependency for the same reason SYSHash's
/// SHA-256 is: SYSKit has zero external packages so it keeps building and
/// testing on Linux CI with no Xcode.
public enum SYSZip {

    public enum ZipError: Error {
        case notAZip
        case unsupportedCompressionMethod(UInt16)
        case corruptEntry(String)
        case decompressionUnavailable
    }

    /// Extracts every entry in the zip at `source` into `destination`
    /// (created if needed).
    ///
    /// If every entry in the archive sits under the same single top-level
    /// folder, that folder is dropped — a common zip convention (many zip
    /// tools wrap a folder's contents this way when compressing it), and a
    /// caller extracting one archive's worth of content into its own
    /// destination folder almost never wants that folder nested one level
    /// inside another copy of itself.
    public static func unzip(at source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let entries = stripCommonRoot(try readCentralDirectory(data))
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for entry in entries {
            guard !entry.path.isEmpty else { continue }
            let outURL = destination.appendingPathComponent(entry.path)
            if entry.path.hasSuffix("/") {
                try fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let contents = try extract(entry, from: data)
            try contents.write(to: outURL, options: .atomic)
        }
    }

    private static func stripCommonRoot(_ entries: [Entry]) -> [Entry] {
        guard let first = entries.first,
              let slashIndex = first.path.firstIndex(of: "/")
        else { return entries }

        let root = first.path[...slashIndex]
        guard entries.allSatisfy({ $0.path.hasPrefix(root) }) else { return entries }

        return entries.map { entry in
            Entry(
                path: String(entry.path.dropFirst(root.count)),
                method: entry.method,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                localHeaderOffset: entry.localHeaderOffset)
        }
    }

    // MARK: - Central directory

    private struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        guard let eocdOffset = findEOCD(data) else { throw ZipError.notAZip }
        let entryCount = Int(data.sysReadUInt16(at: eocdOffset + 10))
        var offset = Int(data.sysReadUInt32(at: eocdOffset + 16))

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        for _ in 0 ..< entryCount {
            guard offset + 46 <= data.count, data.sysReadUInt32(at: offset) == 0x02014b50 else {
                throw ZipError.corruptEntry("central directory entry \(entries.count)")
            }
            let method = data.sysReadUInt16(at: offset + 10)
            let compSize = Int(data.sysReadUInt32(at: offset + 20))
            let uncompSize = Int(data.sysReadUInt32(at: offset + 24))
            let nameLen = Int(data.sysReadUInt16(at: offset + 28))
            let extraLen = Int(data.sysReadUInt16(at: offset + 30))
            let commentLen = Int(data.sysReadUInt16(at: offset + 32))
            let localOffset = Int(data.sysReadUInt32(at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.corruptEntry("central directory filename") }
            let nameData = data.subdata(in: nameStart ..< (nameStart + nameLen))
            let path = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            entries.append(Entry(
                path: path, method: method,
                compressedSize: compSize, uncompressedSize: uncompSize,
                localHeaderOffset: localOffset))

            offset = nameStart + nameLen + extraLen + commentLen
        }
        return entries
    }

    /// Scans backward for the End Of Central Directory signature — it can
    /// sit after an archive comment of up to 65535 bytes, so it is not
    /// simply the file's last 22 bytes.
    private static func findEOCD(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let floor = max(0, data.count - 22 - 65535)
        var i = data.count - 22
        while i >= floor {
            if data[i] == 0x50, data[i + 1] == 0x4b, data[i + 2] == 0x05, data[i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Per-entry extraction

    private static func extract(_ entry: Entry, from data: Data) throws -> Data {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= data.count, data.sysReadUInt32(at: offset) == 0x04034b50 else {
            throw ZipError.corruptEntry(entry.path)
        }
        let nameLen = Int(data.sysReadUInt16(at: offset + 26))
        let extraLen = Int(data.sysReadUInt16(at: offset + 28))
        let dataStart = offset + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= data.count else { throw ZipError.corruptEntry(entry.path) }
        let compressed = data.subdata(in: dataStart ..< (dataStart + entry.compressedSize))

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, uncompressedSize: entry.uncompressedSize, path: entry.path)
        default:
            throw ZipError.unsupportedCompressionMethod(entry.method)
        }
    }

    /// Raw DEFLATE (RFC 1951) — what ZIP's compression method 8 stores, and,
    /// despite the name, what Apple's `COMPRESSION_ZLIB` algorithm decodes
    /// (no zlib/gzip header or trailer, unlike the actual zlib format).
    private static func inflate(_ compressed: Data, uncompressedSize: Int, path: String) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        #if canImport(Compression)
        var output = Data(count: uncompressedSize)
        let decodedCount = output.withUnsafeMutableBytes { outBuf -> Int in
            compressed.withUnsafeBytes { inBuf -> Int in
                guard let outPtr = outBuf.bindMemory(to: UInt8.self).baseAddress,
                      let inPtr = inBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    outPtr, uncompressedSize,
                    inPtr, compressed.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard decodedCount == uncompressedSize else { throw ZipError.corruptEntry(path) }
        return output
        #else
        throw ZipError.decompressionUnavailable
        #endif
    }
}

private extension Data {
    func sysReadUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func sysReadUInt32(at offset: Int) -> UInt32 {
        UInt32(self[startIndex + offset])
            | (UInt32(self[startIndex + offset + 1]) << 8)
            | (UInt32(self[startIndex + offset + 2]) << 16)
            | (UInt32(self[startIndex + offset + 3]) << 24)
    }
}
