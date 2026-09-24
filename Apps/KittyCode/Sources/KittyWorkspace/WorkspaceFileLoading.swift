import AemiIO
public import AtelierText
import Darwin
public import Foundation

public struct LoadedFile: Sendable {
    public let content: String
    /// `content` as a rope, built where the file is read so that opening it only installs the rope on the main actor.
    public let textBuffer: TextBuffer
    public let lineEnding: TextDocument.LineEnding

    /// - Complexity: O(n) in the UTF-8 length of `content`, to build its rope.
    public init(content: String, lineEnding: TextDocument.LineEnding) {
        self.content = content
        self.textBuffer = TextBuffer(content)
        self.lineEnding = lineEnding
    }
}

/// Runs one blocking file read off the cooperative pool, the way the app's `BlockingOffloadPool.run` does, and returns
/// what the read returns: the file's text.
public typealias BlockingFileRead =
    @Sendable (_ read: @escaping @Sendable () throws -> LoadedFile) async throws -> LoadedFile

/// What a read asks of an open file: its size, then its bytes, copied with `pread` into memory the editor owns. A
/// mapping would let another process that truncates the file between the two calls turn the next page touched into
/// SIGBUS, which takes the editor and every unsaved buffer down with it; a short `pread` is an error instead.
/// ``PosixFile`` is the one real conformer, and a test's double truncates its file between the two calls.
protocol PositionalFile {
    func fileSize() throws -> Int
    func pread(into buffer: UnsafeMutableRawBufferPointer, at offset: Int) throws
}

extension PosixFile: PositionalFile {}

public enum WorkspaceFileLoading {
    public static let maxFileSize = 50_000_000  // 50MB

    /// Reads the UTF-8 file at `path` for an open or a reload, on the thread `offload` runs it on.
    /// - Parameters:
    ///   - path: The file to read.
    ///   - maximumSize: A file larger than this is refused before any of it is read.
    ///   - offload: Runs the blocking read: the app's pool, never a cooperative thread.
    /// - Returns: The text with every line break as LF, the one break a buffer holds, its rope, built on the thread
    ///   `offload` runs the read on, and the line ending the file used, which a save writes back.
    /// - Throws: `CancellationError`; `CocoaError(.fileReadTooLarge)` past `maximumSize`;
    ///   `CocoaError(.fileReadInapplicableStringEncoding)` when the file is not UTF-8; otherwise the `CocoaError`
    ///   Foundation's own reads give, a file that shrank while it was read among them.
    public static func readUTF8File(
        at path: String, maximumSize: Int = maxFileSize, offload: BlockingFileRead
    ) async throws -> LoadedFile {
        try Task.checkCancellation()
        return try await offload { try decode(try contents(atPath: path, maximumSize: maximumSize)) }
    }

    /// The bytes of the file at `path`; see ``contents(of:maximumSize:)``.
    /// - Throws: As ``readUTF8File(at:maximumSize:offload:)``, but for the encoding.
    static func contents(atPath path: String, maximumSize: Int) throws -> Data {
        do {
            let file = try PosixFile(path: path, mode: .readOnly)
            defer { file.close() }
            return try contents(of: file, maximumSize: maximumSize)
        } catch let error as IOError {
            throw CocoaError.error(readErrorCode(for: error.errno), url: URL(fileURLWithPath: path))
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            throw CocoaError.error(.fileReadTooLarge, url: URL(fileURLWithPath: path))
        }
    }

    /// The bytes of `file`, copied with `pread` into memory this call owns.
    /// - Throws: `CocoaError(.fileReadTooLarge)` past `maximumSize`, before any byte is read; the file's error
    ///   otherwise, a short read when the file shrank after it was sized.
    static func contents(of file: some PositionalFile, maximumSize: Int) throws -> Data {
        let size = try file.fileSize()
        guard size <= maximumSize else { throw CocoaError(.fileReadTooLarge) }
        var data = Data(count: size)
        try data.withUnsafeMutableBytes { try file.pread(into: $0, at: 0) }
        return data
    }

    private static func readErrorCode(for errno: Int32) -> CocoaError.Code {
        switch errno {
            case ENOENT, ENOTDIR: .fileReadNoSuchFile
            case EACCES, EPERM: .fileReadNoPermission
            default: .fileReadUnknown
        }
    }

    /// The UTF-8 text of a file's bytes, with every line break as LF, its rope, and the line ending the bytes used.
    /// - Throws: `CocoaError(.fileReadInapplicableStringEncoding)` when `data` is not UTF-8.
    /// - Complexity: O(n) in the size of `data`.
    static func decode(_ data: Data) throws -> LoadedFile {
        let lineEnding = TextDocument.detectLineEnding(in: data)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return LoadedFile(content: TextDocument.normalizingLineBreaks(content), lineEnding: lineEnding)
    }

    /// The modification date of the file at `path`, or nil when it cannot be read, a missing file included. Every
    /// comparison of a buffer with its file reads the date here, so an untouched file always reads back the same date.
    public static func modificationDate(ofFileAt path: String) -> Date? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
