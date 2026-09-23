public import AemiCore
public import AtelierText
import Foundation

public struct LoadedFile: Sendable {
    public let content: String
    public let lineEnding: TextDocument.LineEnding

    public init(content: String, lineEnding: TextDocument.LineEnding) {
        self.content = content
        self.lineEnding = lineEnding
    }
}

public enum WorkspaceFileLoading {
    public static let maxFileSize = 50_000_000  // 50MB

    /// Reads the UTF-8 file at `path` off the caller's actor, for an open or a reload.
    /// - Returns: The text with every line break as LF, the one break a buffer holds, and the line ending the file
    ///   used, which a save writes back.
    /// - Throws: `CancellationError`, the read's error, or `CocoaError(.fileReadInapplicableStringEncoding)` when the
    ///   file is not UTF-8.
    public static func readUTF8File(
        at path: String, taskProvider: any TaskProvider = .default
    ) async throws -> LoadedFile {
        try await taskProvider.detachedTask(role: .work, priority: .userInitiated) {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try Task.checkCancellation()
            return try decode(data)
        }
        .value
    }

    /// The UTF-8 text of a file's bytes, with every line break as LF, and the line ending the bytes used.
    /// - Throws: `CocoaError(.fileReadInapplicableStringEncoding)` when `data` is not UTF-8.
    /// - Complexity: O(n) in the size of `data`.
    static func decode(_ data: Data) throws -> LoadedFile {
        let lineEnding = TextDocument.detectLineEnding(in: data)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return LoadedFile(content: TextDocument.normalizingLineBreaks(content), lineEnding: lineEnding)
    }
}
