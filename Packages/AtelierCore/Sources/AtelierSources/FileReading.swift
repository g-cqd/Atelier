import AemiIO
import CryptoKit
import Darwin
import Foundation

/// What a read asks of an open file: its size, then its bytes at an offset, copied with `pread` into memory the
/// reader owns. A mapping would let another process that truncates the file between the two calls turn the next page
/// touched into SIGBUS; a short `pread` is an error instead. ``PosixFile`` is the one real conformer, and a test's
/// double truncates its file between the two calls.
protocol PositionalFile {
    func fileSize() throws -> Int
    func pread(into buffer: UnsafeMutableRawBufferPointer, at offset: Int) throws
}

extension PosixFile: PositionalFile {}

extension SourceLoader {
    /// Bytes hashed per `pread`: a large source file takes a few calls, and the chunk stays in cache while SHA-1
    /// consumes it.
    static let hashingChunkSize = 64 * 1024

    /// The object id git would assign to `file`'s contents as a blob, read front to back in chunks. The size in the
    /// blob header is the one `file` reports, so a file that grows during the read hashes as its first `size` bytes.
    /// - Throws: The file's error; a short read when the file shrank after it was sized.
    static func blobID(of file: some PositionalFile) throws -> String {
        let size = try file.fileSize()
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(size)\0".utf8))
        var chunk = [UInt8](repeating: 0, count: min(size, hashingChunkSize))
        try chunk.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < size {
                let window = UnsafeMutableRawBufferPointer(rebasing: buffer[..<min(buffer.count, size - offset)])
                try file.pread(into: window, at: offset)
                hasher.update(bufferPointer: UnsafeRawBufferPointer(window))
                offset += window.count
            }
        }
        return hex(hasher.finalize())
    }

    /// The whole contents of `file`, copied with `pread` into memory this call owns.
    /// - Throws: The file's error; a short read when the file shrank after it was sized.
    static func contents(of file: some PositionalFile) throws -> Data {
        var data = Data(count: try file.fileSize())
        try data.withUnsafeMutableBytes { try file.pread(into: $0, at: 0) }
        return data
    }

    /// The whole contents of the file at `path`; see ``contents(of:)``.
    /// - Throws: `CocoaError` when the file cannot be opened, measured or read to its end, with the code and message
    ///   Foundation's own reads give, such as "The file “a.swift” couldn't be opened because there is no such file.",
    ///   since the app shows that message.
    static func contents(atPath path: String) throws -> Data {
        do {
            let file = try PosixFile(path: path, mode: .readOnly)
            defer { file.close() }
            return try contents(of: file)
        } catch let error as IOError {
            throw CocoaError.error(readErrorCode(for: error.errno), url: URL(filePath: path))
        }
    }

    private static func readErrorCode(for errno: Int32) -> CocoaError.Code {
        switch errno {
            case ENOENT, ENOTDIR: .fileReadNoSuchFile
            case EACCES, EPERM: .fileReadNoPermission
            default: .fileReadUnknown
        }
    }
}
