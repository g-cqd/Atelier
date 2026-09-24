import AtelierSwiftSyntax
import SwiftParser
import SwiftSyntax
import Synchronization

/// Finds the identifier token under a text position, for hover and similar source-only lookups that only know a
/// line and column.
public enum IdentifierLocator {
    /// The identifier token covering `(line, utf16Column)`, zero-based; `nil` for keywords, literals, operators,
    /// trivia (including surrounding whitespace), or a position outside the document.
    /// - Complexity: O(n) in the length of `content`, which is parsed on every call; ``ParsedSourceCache`` keeps a
    ///   parse for repeated lookups in one document.
    public static func identifier(in content: String, line: Int, utf16Column: Int) -> String? {
        SwiftSyntaxStack.run {
            let source = ParsedSource(content: content, tree: Parser.parse(source: content))
            return identifier(in: source, line: line, utf16Column: utf16Column)
        }
    }

    /// The identifier token covering `(line, utf16Column)` in an already parsed document. The token search descends
    /// the tree, so call this on ``AtelierSwiftSyntax/SwiftSyntaxStack``.
    static func identifier(in source: ParsedSource, line: Int, utf16Column: Int) -> String? {
        guard let offset = source.utf8Offset(line: line, utf16Column: utf16Column),
            let token = source.tree.token(at: AbsolutePosition(utf8Offset: offset))
        else { return nil }
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
}

/// A document parsed for identifier lookups: its syntax tree, and the UTF-8 offset each line starts at, both built
/// once so a lookup costs a token search.
struct ParsedSource: Sendable {
    let content: String
    let tree: SourceFileSyntax
    /// The UTF-8 offset of each line's first byte. Lines end at `\n`, as the diff numbers them, so a CRLF file's
    /// lines are found too.
    let lineStarts: [Int]

    init(content: String, tree: SourceFileSyntax) {
        self.content = content
        self.tree = tree
        var lineStarts = [0]
        var offset = 0
        for byte in content.utf8 {
            offset += 1
            if byte == UInt8(ascii: "\n") { lineStarts.append(offset) }
        }
        self.lineStarts = lineStarts
    }

    /// Converts a zero-based (line, UTF-16 column) position to a UTF-8 byte offset into ``content``, or nil when it
    /// falls outside the document.
    func utf8Offset(line: Int, utf16Column: Int) -> Int? {
        guard line >= 0, utf16Column >= 0, line < lineStarts.count else { return nil }
        let utf8 = content.utf8
        let lineStart = utf8.index(utf8.startIndex, offsetBy: lineStarts[line])
        let lineEnd =
            line + 1 < lineStarts.count
            ? utf8.index(utf8.startIndex, offsetBy: lineStarts[line + 1] - 1) : utf8.endIndex
        let lineText = content[lineStart ..< lineEnd]
        guard
            let columnIndex = lineText.utf16.index(
                lineText.utf16.startIndex, offsetBy: utf16Column, limitedBy: lineText.utf16.endIndex
            )
        else { return nil }
        return lineStarts[line] + lineText.utf8.distance(from: lineText.utf8.startIndex, to: columnIndex)
    }
}

/// The document a hover provider parsed last, kept so a pointer resting over one file parses it once rather than on
/// every hover. One document at a time bounds what it holds.
final class ParsedSourceCache: Sendable {
    private let last = Mutex<ParsedSource?>(nil)
    private let parse: @Sendable (String) -> SourceFileSyntax

    /// - Parameter parse: Parses a document; swift-syntax unless a test counts the parses.
    init(parse: @escaping @Sendable (String) -> SourceFileSyntax = { Parser.parse(source: $0) }) {
        self.parse = parse
    }

    /// `content` parsed, from the cache when it is the document parsed last. A parse recurses as deep as the document
    /// nests, so call this on ``AtelierSwiftSyntax/SwiftSyntaxStack``.
    func source(for content: String) -> ParsedSource {
        if let cached = last.withLock({ $0 }), cached.content == content { return cached }
        let source = ParsedSource(content: content, tree: parse(content))
        last.withLock { $0 = source }
        return source
    }
}
