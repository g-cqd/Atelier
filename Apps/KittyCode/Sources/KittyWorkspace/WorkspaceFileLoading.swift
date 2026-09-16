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

    public static func readUTF8File(at path: String) async throws -> LoadedFile {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try Task.checkCancellation()
            let lineEnding = TextDocument.detectLineEnding(in: data)

            guard let content = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return LoadedFile(content: content, lineEnding: lineEnding)
        }
        .value
    }
}
