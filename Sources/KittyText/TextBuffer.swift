import Foundation

/// A text buffer backed by an array of lines.
///
/// This is a simple v1 implementation. A PieceTable or rope-backed
/// variant would be more efficient for large documents.
public struct TextBuffer: Sendable {
    public var lines: [String]

    public init(_ content: String = "") {
        self.lines = content.isEmpty ? [""] : content.components(separatedBy: "\n")
    }

    public init(lines: [String]) {
        self.lines = lines.isEmpty ? [""] : lines
    }

    public var lineCount: Int { lines.count }

    public var isEmpty: Bool { lines.count == 1 && lines[0].isEmpty }

    /// Returns the line at the given index, or an empty string if out of bounds.
    public func line(at index: Int) -> String {
        guard lines.indices.contains(index) else { return "" }
        return lines[index]
    }

    /// Reconstructs the full text by joining lines with newlines.
    public var text: String { lines.joined(separator: "\n") }
}
