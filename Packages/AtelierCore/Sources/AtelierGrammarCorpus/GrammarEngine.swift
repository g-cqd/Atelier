public import AtelierParser
public import AtelierQuery
public import AtelierSyntaxModel

/// One language's grammar, ready to highlight: a parser over its compiled tables, its highlight query with each
/// capture's role, and the external scanner its grammar calls for. ``GrammarTier`` and KittyCode's
/// `LanguageHighlighter` both parse, gate and query through it.
public struct GrammarEngine: Sendable {
    /// The largest text, in UTF-8 bytes, highlighted from its grammar; a larger one keeps the lexer's colour, which
    /// spares the parse and the per-byte arrays of the merge.
    public static let maxSourceBytes = 512_000

    /// The share of a text's bytes, in percent, under ERROR nodes at which its parse is not used for colour.
    ///
    /// Valid code that its grammar reads leaves little under ERROR nodes: 0.6% of `ltdl.c`, 9 of 200,220 bytes in 27
    /// of this repository's Swift files, none of 176,667 bytes of JavaScript and Python. A parse that goes wrong leaves
    /// far more: the parser of an earlier revision left 12.6% to 96.5% of 26 of those Swift files under ERROR nodes.
    /// Between the two, 5% keeps the grammar through a few misread constructs and drops it for a text it fails on.
    public static let maxErrorBytePercent = 5

    public let parser: GrammarParser
    public let query: Query
    /// The role of each of `query`'s capture names.
    public let roles: CaptureRoles
    /// The bundled scanner the grammar's `externals` need; nil for a grammar without any.
    public let scannerType: (any GrammarExternalScanner.Type)?
    /// The grammar's identity: its language, the hash of its `grammar.json` and the compiler's format version. It
    /// changes whenever the tables would.
    public let grammarKey: String

    /// The engine of `artifacts`; nil when its grammar needs an external scanner that is not bundled, whose tables are
    /// then empty.
    public init?(_ artifacts: SyntaxArtifacts) {
        guard !artifacts.needsExternalScanner else { return nil }
        parser = GrammarParser(
            parseTable: artifacts.parseTable, lexTable: artifacts.lexTable, productions: artifacts.productions)
        query = artifacts.query
        roles = artifacts.roles
        scannerType = artifacts.scannerType
        grammarKey = artifacts.grammarKey
    }

    /// A scanner in its initial state, for one parse; nil for a grammar without external tokens.
    public func makeScanner() -> (any GrammarExternalScanner)? {
        scannerType?.init()
    }

    /// Parses `source` whole, honouring the calling task's cancellation (``GrammarParser/parse(_:externalScanner:)``).
    /// - Throws: The parser's `ParseError`, `.cancelled` among them.
    public func parse(
        _ source: String, externalScanner: (any GrammarExternalScanner)?
    ) throws(ParseError) -> SyntaxTree {
        try parser.parse(source, externalScanner: externalScanner)
    }

    /// Whether `tree`'s colour is used: the parse reduced to the grammar's start rule, and less than
    /// ``maxErrorBytePercent`` percent of its bytes lie under ERROR nodes.
    /// - Complexity: O(1): the parse counted its ERROR bytes as it built the tree.
    public static func passesQualityGate(_ tree: SyntaxTree) -> Bool {
        tree.root.type != "_start"
            && (tree.errorByteCount == 0 || tree.errorByteCount * 100 < tree.source.utf8.count * maxErrorBytePercent)
    }

    /// The share of `tree`'s bytes under ERROR nodes, in percent, rounded down.
    public static func errorBytePercent(of tree: SyntaxTree) -> Int {
        let bytes = tree.source.utf8.count
        return bytes == 0 ? 0 : tree.errorByteCount * 100 / bytes
    }

    /// The query's tokens over `tree`, overlapping as the captures do, or only those of nodes that overlap
    /// `byteRange` when one is given (``tokens(matches:roles:layer:)``).
    public func tokens(
        in tree: SyntaxTree, byteRange: Range<Int>? = nil, layer: HighlightLayer = .structural
    ) -> [HighlightToken] {
        let matches =
            byteRange.map { QueryMatcher.execute(query: query, tree: tree, byteRange: $0) }
            ?? QueryMatcher.execute(query: query, tree: tree)
        return Self.tokens(matches: matches, roles: roles, layer: layer)
    }

    /// A token in `layer` for every capture in `matches` that colours text, with the role `roles` holds for the
    /// capture's index; an earlier query pattern gets a higher priority, so it wins on identical ranges.
    /// - Returns: The tokens in match order, ranges in the source's bytes.
    public static func tokens(
        matches: [QueryMatch], roles: CaptureRoles, layer: HighlightLayer = .structural
    ) -> [HighlightToken] {
        let maxPatternIndex = matches.map(\.patternIndex).max() ?? 0
        var tokens: [HighlightToken] = []
        tokens.reserveCapacity(matches.reduce(into: 0) { $0 += $1.captures.count })
        for match in matches {
            for capture in match.captures {
                guard let resolved = roles[capture.index] else { continue }
                tokens.append(
                    HighlightToken(
                        byteRange: capture.node.byteRange, role: resolved.role, modifiers: resolved.modifiers,
                        layer: layer, priority: maxPatternIndex - match.patternIndex))
            }
        }
        return tokens
    }

    /// The bundled corpus's name for `language`'s grammar; nil for a language no grammar ships for, or one whose
    /// grammar the corpus cannot use.
    public static func grammarName(of language: Language) -> String? {
        switch language {
            case .shell: "bash"
            case .plain, .objectiveC, .fish: nil
            default: language.name
        }
    }
}
