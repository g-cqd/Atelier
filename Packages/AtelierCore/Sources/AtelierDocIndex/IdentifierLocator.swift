import SwiftParser
import SwiftSyntax

/// Finds the identifier token under a text position, for hover and similar source-only lookups that only know a
/// line and column.
public enum IdentifierLocator {
    /// The identifier token covering `(line, utf16Column)`, zero-based; `nil` for keywords, literals, operators,
    /// trivia (including surrounding whitespace), or a position outside the document.
    /// - Complexity: O(n) in the length of `content`, which is parsed on every call.
    public static func identifier(in content: String, line: Int, utf16Column: Int) -> String? {
        guard let offset = utf8Offset(in: content, line: line, utf16Column: utf16Column) else { return nil }
        let tree = Parser.parse(source: content)
        guard let token = tree.token(at: AbsolutePosition(utf8Offset: offset)) else { return nil }
        // `token(at:)` matches trivia too, so require the position to fall within the token's own text.
        let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = token.endPositionBeforeTrailingTrivia.utf8Offset
        guard offset >= start, offset < end else { return nil }
        guard case .identifier(let text) = token.tokenKind else { return nil }
        return stripBackticks(text)
    }

    private static func stripBackticks(_ text: String) -> String {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count > 1 else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// Converts a zero-based (line, UTF-16 column) position to a UTF-8 byte offset into `content`, or nil when it
    /// falls outside the document.
    private static func utf8Offset(in content: String, line: Int, utf16Column: Int) -> Int? {
        guard line >= 0, utf16Column >= 0 else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard line < lines.count else { return nil }
        var offset = 0
        for index in 0 ..< line {
            offset += lines[index].utf8.count + 1
        }
        let lineText = lines[line]
        guard
            let columnIndex = lineText.utf16.index(
                lineText.utf16.startIndex, offsetBy: utf16Column, limitedBy: lineText.utf16.endIndex
            )
        else { return nil }
        offset += lineText.utf8.distance(from: lineText.utf8.startIndex, to: columnIndex)
        return offset
    }
}
