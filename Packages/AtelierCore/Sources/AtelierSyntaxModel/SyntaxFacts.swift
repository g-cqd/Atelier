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

/// A brace pair that opens a scope (DIFF-03): where it lies and what it holds.
public struct SyntaxScope: Sendable, Equatable {
    /// What a scope's braces hold.
    public enum Kind: Sendable, Equatable {
        /// A type's or an extension's members.
        case type
        /// A function's, an initializer's or an accessor's body.
        case function
        case closure
        /// The body of an `if`, a loop, a `switch` and the like.
        case controlFlow
        /// Braces whose owner is unknown, as the lexer's are.
        case block
    }

    /// From the opening brace to past the closing one, in UTF-8 bytes of the text.
    public let range: Range<Int>
    public let kind: Kind

    public init(range: Range<Int>, kind: Kind) {
        self.range = range
        self.kind = kind
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
    /// Every brace pair that opens a scope, by its opening brace, an enclosing scope before those it holds.
    public let scopes: [SyntaxScope]

    public init(
        tokenBoundaries: [[Range<Int>]], declarations: [SyntaxDeclaration], highlights: [HighlightToken]?,
        unexpectedShare: Double, scopes: [SyntaxScope] = []
    ) {
        self.tokenBoundaries = tokenBoundaries
        self.declarations = declarations
        self.highlights = highlights
        self.unexpectedShare = unexpectedShare
        self.scopes = scopes
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
        return Self.arrayHeader * 4 + tokenBoundaries.capacity * MemoryLayout<[Range<Int>]>.stride + lines
            + declarations.capacity * MemoryLayout<SyntaxDeclaration>.stride + strings
            + (highlights?.capacity ?? 0) * MemoryLayout<HighlightToken>.stride
            + scopes.capacity * MemoryLayout<SyntaxScope>.stride
    }

    /// What an array's storage costs besides its elements.
    private static let arrayHeader = 32
}

/// What each span a language server named is (PERF-11 step 8): a keyword, a literal, a comment or a symbol, in UTF-8
/// bytes of the text, so that hover asks the server over a symbol alone.
public struct SymbolKinds: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case keyword
        /// A string, a number or a Boolean.
        case literal
        case comment
        /// A name the server resolved: a type, a function, a variable and the like.
        case symbol
    }

    /// The spans, ascending and disjoint, in UTF-8 bytes of the text.
    public let ranges: [Range<Int>]
    public let kinds: [Kind]

    /// The kinds of `tokens`, ascending and disjoint; an operator or punctuation token, which says nothing about what
    /// hover could ask, is left out.
    public init(tokens: [HighlightToken]) {
        var ranges: [Range<Int>] = []
        var kinds: [Kind] = []
        for token in tokens {
            guard let kind = Self.kind(of: token.role) else { continue }
            ranges.append(token.byteRange)
            kinds.append(kind)
        }
        self.ranges = ranges
        self.kinds = kinds
    }

    /// The kind of the span covering the UTF-8 byte `offset`; nil where no span does.
    /// - Complexity: O(log spans)
    public func kind(atUTF8 offset: Int) -> Kind? {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < ranges.count, ranges[low].contains(offset) else { return nil }
        return kinds[low]
    }

    /// An estimate of the memory the spans hold, which the facts store bounds.
    public var estimatedBytes: Int {
        64 + ranges.capacity * MemoryLayout<Range<Int>>.stride + kinds.capacity * MemoryLayout<Kind>.stride
    }

    /// The kind a token of `role` names; nil for an operator or punctuation.
    public static func kind(of role: HighlightRole) -> Kind? {
        switch role {
            case .keyword, .keywordFunction, .keywordReturn, .keywordOperator: .keyword
            case .string, .stringSpecial, .stringEscape, .number, .numberFloat, .regex, .boolean, .escape: .literal
            case .comment, .commentDocumentation: .comment
            case .operator, .punctuationBracket, .punctuationDelimiter, .punctuationSpecial: nil
            default: .symbol
        }
    }
}
