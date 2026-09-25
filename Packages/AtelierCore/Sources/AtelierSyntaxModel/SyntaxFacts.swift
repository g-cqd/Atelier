/// A declaration a parse found (PERF-11 step 3): what it declares, where, and its documentation.
public struct SyntaxDeclaration: Sendable, Equatable {
    /// What a declaration declares.
    public enum Kind: Sendable, Equatable {
        case type
        case function
        case initializer
        case `subscript`
        case variable
        case enumCase
        case typeAlias
        case macro
    }

    /// The declared identifier, without backticks, or `init` and `subscript`.
    public let name: String
    public let kind: Kind
    /// The whole declaration, attributes and modifiers included, in UTF-8 bytes of the text; its doc comment is not.
    public let range: Range<Int>
    /// The doc comment above it, its markers stripped, as markdown; nil when it has none.
    public let documentation: String?
    /// The declaration's head with its body cut off, whitespace collapsed; kept only for a documented declaration,
    /// the one hover shows.
    public let signature: String?

    public init(name: String, kind: Kind, range: Range<Int>, documentation: String?, signature: String?) {
        self.name = name
        self.kind = kind
        self.range = range
        self.documentation = documentation
        self.signature = signature
    }
}

/// What one parse of a text learned, kept per revision in a ``SyntaxFactsStore`` so that colour, intraline boundaries
/// and hover share one parse (PERF-11 step 3, design note section 3.4).
public struct SyntaxFacts: Sendable {
    /// Each line's token boundaries, in UTF-16 offsets from the line's start: what the syntax granularity of the
    /// intraline diff splits changed lines at.
    public let tokenBoundaries: [[Range<Int>]]
    /// Every declaration, in source order.
    public let declarations: [SyntaxDeclaration]
    /// The colour tier's tokens over the whole text, in UTF-8 offsets; nil when the text failed the tier's gate.
    public let highlights: [HighlightToken]?
    /// The share of the text's bytes in unexpected nodes.
    public let unexpectedShare: Double

    public init(
        tokenBoundaries: [[Range<Int>]], declarations: [SyntaxDeclaration], highlights: [HighlightToken]?,
        unexpectedShare: Double
    ) {
        self.tokenBoundaries = tokenBoundaries
        self.declarations = declarations
        self.highlights = highlights
        self.unexpectedShare = unexpectedShare
    }

    /// An estimate of the memory the facts hold, their arrays' storage at its capacity and their strings' bytes, which
    /// the store bounds; `SyntaxFactsMemoryBenchmark` compares it with what the allocator reports for them.
    /// - Complexity: O(lines + declarations)
    public var estimatedBytes: Int {
        let lines = tokenBoundaries.reduce(0) {
            $0 + Self.arrayHeader + $1.capacity * MemoryLayout<Range<Int>>.stride
        }
        let strings = declarations.reduce(0) { total, declaration in
            total + declaration.name.utf8.count + (declaration.documentation?.utf8.count ?? 0)
                + (declaration.signature?.utf8.count ?? 0)
        }
        return Self.arrayHeader * 3 + tokenBoundaries.capacity * MemoryLayout<[Range<Int>]>.stride + lines
            + declarations.capacity * MemoryLayout<SyntaxDeclaration>.stride + strings
            + (highlights?.capacity ?? 0) * MemoryLayout<HighlightToken>.stride
    }

    /// What an array's storage costs besides its elements.
    private static let arrayHeader = 32
}
