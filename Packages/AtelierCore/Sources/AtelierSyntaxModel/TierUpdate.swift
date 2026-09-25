/// What a tier's result is fresh for (PERF-11): a document, the language it was read as, and either the content's key
/// or the document's version. A result for one revision never applies to another, so choosing another language
/// (LANG-01) or changing the text makes a new revision.
public struct SourceRevision: Hashable, Sendable {
    /// How a revision tells one text of a document from another.
    public enum Key: Hashable, Sendable {
        /// A hash of the content, a blob id: a result stays valid for as long as it is kept.
        case content(String)
        /// An editor's document version, which grows with every edit.
        case version(Int)
    }

    public let documentID: String
    public let language: Language
    public let key: Key

    public init(documentID: String, language: Language, key: Key) {
        self.documentID = documentID
        self.language = language
        self.key = key
    }
}

/// Whether a tier speaks for every byte of the lines it covers.
public enum TierCoverage: Sendable, Hashable {
    /// Every byte: a byte without a token is plain text on purpose, so the layers below it are dropped on its lines.
    case complete
    /// Only the bytes its tokens cover, such as a language server's semantic tokens; the layers below show elsewhere.
    case sparse
}

/// The unit a request wants its tokens' offsets in.
public enum TokenUnit: Sendable, Hashable {
    case utf8
    case utf16
}

/// One text a tier job highlights: its revision, its content, where its lines lie, and which of them show.
public struct TierRequest: Sendable {
    public let revision: SourceRevision
    public let text: String
    /// Each line's text within `text`, in UTF-8 bytes, ascending and disjoint, without its line break.
    public let lineRanges: [Range<Int>]
    /// The lines on screen, which every tier emits first.
    public let visibleLines: Range<Int>
    /// The unit of the offsets in the updates' tokens, each from its line's start.
    public let unit: TokenUnit

    public init(
        revision: SourceRevision, text: String, lineRanges: [Range<Int>], visibleLines: Range<Int>,
        unit: TokenUnit = .utf8
    ) {
        self.revision = revision
        self.text = text
        self.lineRanges = lineRanges
        self.visibleLines = visibleLines.clamped(to: 0 ..< lineRanges.count)
        self.unit = unit
    }

    /// The chunks a tier emits in: the visible lines first, then the lines after them, then those before; empty
    /// chunks left out.
    public var chunks: [Range<Int>] {
        let all = 0 ..< lineRanges.count
        return [visibleLines, visibleLines.upperBound ..< all.upperBound, all.lowerBound ..< visibleLines.lowerBound]
            .filter { !$0.isEmpty }
    }

    /// `tokens`, found over the whole of ``text`` in UTF-8 byte offsets, ascending and disjoint, cut into `lines`
    /// and moved to ``unit``: what an update over those lines carries.
    /// - Complexity: O(tokens + bytes of `lines`)
    public func lineTokens(_ tokens: [HighlightToken], lines: Range<Int>) -> LineTokens {
        inUnit(LineTokens(tokens, lineRanges: Array(lineRanges[lines])), lines: lines)
    }

    /// `tokens`, one entry per line of `lines` in UTF-8 byte offsets from each line's start, moved to ``unit``.
    /// - Complexity: O(1) for UTF-8 or an ASCII text; else O(tokens + bytes of `lines`)
    public func inUnit(_ tokens: LineTokens, lines: Range<Int>) -> LineTokens {
        guard unit == .utf16 else { return tokens }
        let utf8 = text.utf8Span
        guard !utf8.isKnownASCII else { return tokens }
        var moved = tokens
        moved.moveToUTF16(over: utf8.span, lineRanges: Array(lineRanges[lines]))
        return moved
    }
}

/// What a tier emits: its tokens for some lines of one revision.
public struct TierUpdate: Sendable {
    public let layer: HighlightLayer
    public let coverage: TierCoverage
    /// The revision the tier read.
    public let revision: SourceRevision
    /// The lines the update covers; `tokens[i]` holds line `lines.lowerBound + i`'s.
    public let lines: Range<Int>
    public let tokens: LineTokens

    public init(
        layer: HighlightLayer, coverage: TierCoverage, revision: SourceRevision, lines: Range<Int>, tokens: LineTokens
    ) {
        precondition(tokens.count == lines.count, "an update holds one entry per line it covers")
        self.layer = layer
        self.coverage = coverage
        self.revision = revision
        self.lines = lines
        self.tokens = tokens
    }
}
