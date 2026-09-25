public import AemiCore
import AtelierGrammar
import AtelierLexers
import AtelierParser
import AtelierQuery
public import AtelierSyntaxModel
// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable file_length function_body_length type_body_length
import Foundation
import KittyStyle
import Synchronization
import os

/// Highlighter signposts, so Instruments can attribute frame time to parsing, merging and each kind of highlight.
private let highlighterSignposter = OSSignposter(
    subsystem: "com.kittytui.syntax", category: "highlight")

public enum LanguageHighlighter: Sendable {
    /// Maximum source size in bytes for grammar-backed highlighting.
    /// Beyond this, the session falls back to the lightweight lexical highlighter
    /// to prevent runaway memory from per-byte style arrays and token lists.
    public static let maxGrammarSourceBytes = 512_000  // 512 KB

    /// The share of a document's bytes, in percent, under ERROR nodes at which the document is highlighted lexically
    /// rather than from its grammar, until a parse of a later version of it falls under the share again.
    ///
    /// Valid code that its grammar reads leaves little under ERROR nodes: 0.6% of `ltdl.c`, 9 of 200,220 bytes in 27
    /// of this repository's Swift files, none of 176,667 bytes of JavaScript and Python. A parse that goes wrong leaves
    /// far more: the parser of an earlier revision left 12.6% to 96.5% of 26 of those Swift files under ERROR nodes.
    /// Between the two, 5% keeps the grammar through a few misread constructs and drops it for a document it fails on.
    public static let maxErrorBytePercent = 5

    /// Whether a document is highlighted from `tree`, its parse: the parse reduced to the grammar's start rule, and
    /// less than ``maxErrorBytePercent`` percent of its bytes lie under ERROR nodes.
    /// - Complexity: O(1): the parse counted its ERROR bytes as it built the tree.
    static func passesQualityGate(_ tree: SyntaxTree) -> Bool {
        tree.root.type != "_start"
            && (tree.errorByteCount == 0 || tree.errorByteCount * 100 < tree.source.utf8.count * maxErrorBytePercent)
    }

    public final class Session {
        private enum Strategy {
            case grammar(GrammarSession)
            case fallback
        }

        private final class GrammarSession {
            let parser: GrammarParser
            let scanner: (any GrammarExternalScanner)?
            let query: Query
            /// The role of each of `query`'s capture names, resolved when the language's artifacts loaded.
            let roles: CaptureRoles
            let highlighter: Highlighter
            let scratch = HighlightScratch()
            /// The hash of the last parsed source, the quick check before `parseTree(for:)` reuses `lastParsedTree`.
            var lastParsedSourceHash: Int?
            var lastParsedTree: SyntaxTree?
            /// Whether the last parse passed ``LanguageHighlighter/passesQualityGate(_:)``; false after a parse that
            /// threw, true before any parse.
            private(set) var passesQualityGate = true

            init(artifacts: SyntaxArtifacts, theme: Theme) {
                parser = GrammarParser(
                    parseTable: artifacts.parseTable,
                    lexTable: artifacts.lexTable,
                    productions: artifacts.productions
                )
                scanner = artifacts.scannerType?.init()
                query = artifacts.query
                roles = artifacts.roles
                highlighter = Highlighter(theme: theme)
            }

            /// A parse of `source`, reusing the previous tree when the source is equal to the last one parsed. Every new
            /// parse decides `passesQualityGate` again, so a document that heals goes back to its grammar.
            func parseTree(for source: String) throws(ParseError) -> SyntaxTree {
                let sourceHash = source.hashValue
                if let cached = lastParsedTree,
                    let cachedHash = lastParsedSourceHash,
                    cachedHash == sourceHash,
                    cached.source.utf8.count == source.utf8.count,
                    cached.source == source
                {
                    return cached
                }
                let tree: SyntaxTree
                do {
                    tree = try parser.parse(source, externalScanner: scanner)
                } catch {
                    lastParsedSourceHash = nil
                    lastParsedTree = nil
                    passesQualityGate = false
                    throw error
                }
                lastParsedSourceHash = sourceHash
                lastParsedTree = tree
                passesQualityGate = LanguageHighlighter.passesQualityGate(tree)
                return tree
            }
        }

        private let language: String?
        /// The language the shared lexical engine scans for `language`; plain text yields no lexical tokens.
        private let lexicalLanguage: Language
        private let theme: Theme
        private var strategy: Strategy
        private var splitScratch = SplitLinesScratch()
        /// The theme's style for every role, looked up once, on the session's first highlight.
        private lazy var resolver = RoleBasedThemeResolver(precomputingStylesOf: theme)

        /// Optional semantic token provider (e.g. LSP) for `.semantic` layer merging.
        public var semanticProvider: (any SemanticTokenProvider)?

        /// URI used when requesting semantic tokens from the provider.
        public var documentURI: String?

        public var prefersLineInput: Bool {
            if case .fallback = strategy {
                return true
            }
            return false
        }

        /// Whether the session highlights from its grammar: it has one, and the last document it parsed passed
        /// ``LanguageHighlighter/passesQualityGate(_:)``. A grammar session that has parsed nothing yet is.
        public var isGrammarBacked: Bool {
            if case .grammar(let grammarSession) = strategy {
                return grammarSession.passesQualityGate
            }
            return false
        }

        public init(
            language: String?,
            theme: Theme = .monokai,
            preferGrammar: Bool = true
        ) {
            self.language = language
            self.lexicalLanguage = language.flatMap(Language.init(name:)) ?? .plain
            self.theme = theme

            if preferGrammar,
                let language,
                let artifacts = SyntaxArtifactsCache.artifacts(for: language),
                !artifacts.needsExternalScanner
            {
                strategy = .grammar(GrammarSession(artifacts: artifacts, theme: theme))
            } else {
                strategy = .fallback
            }
        }

        public func highlightDocument(source: String) -> [[StyledSpan]] {
            let interval = highlighterSignposter.beginInterval("highlightDocument")
            defer { highlighterSignposter.endInterval("highlightDocument", interval) }
            return grammarHighlightedDocument(source: source) ?? lexicalLines(source: source)
        }

        /// The lines of `source` highlighted from the grammar alone; nil without a grammar, past
        /// `maxGrammarSourceBytes`, or when the parse throws, is cancelled, or does not pass the quality gate.
        public func grammarHighlightedDocument(source: String) -> [[StyledSpan]]? {
            guard case .grammar(let grammarSession) = strategy,
                source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes,
                let tree = try? grammarSession.parseTree(for: source),
                grammarSession.passesQualityGate
            else { return nil }
            let spans = grammarSession.highlighter.highlight(
                source: source,
                tree: tree,
                query: grammarSession.query,
                scratch: grammarSession.scratch
            )
            return splitDocumentSpans(
                spans,
                source: source,
                defaultStyle: theme.defaultStyle,
                scratch: &splitScratch
            )
        }

        /// The grammar's unresolved structural tokens for `source`; empty without a grammar, past
        /// `maxGrammarSourceBytes`, or when the parse fails or does not pass the quality gate.
        public func highlightDocumentTokens(source: String) -> [HighlightToken] {
            switch strategy {
                case .grammar(let gs):
                    guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                        return []
                    }
                    do {
                        let tree = try gs.parseTree(for: source)
                        guard gs.passesQualityGate else {
                            return []
                        }
                        let matches = QueryMatcher.execute(query: gs.query, tree: tree)
                        return gs.highlighter.buildTokens(matches: matches, roles: gs.roles, layer: .structural)
                    } catch {
                        return []
                    }
                case .fallback:
                    return []
            }
        }

        /// Highlight a document with three-layer merging: lexical baseline,
        /// structural tree-sitter tokens, and optional semantic tokens from LSP.
        /// Lexical tokens always provide a baseline so no text is left unstyled.
        public func highlightDocumentMerged(source: String) async -> [[StyledSpan]] {
            // Layer 0: lexical baseline — always present
            let lexicalTokens = buildLexicalTokens(source: source)

            // Layer 1: structural tree-sitter tokens (may be empty)
            let structuralTokens = highlightDocumentTokens(source: source)

            // Layer 2: semantic tokens from LSP (may be empty)
            var semanticTokens: [HighlightToken] = []
            if let provider = semanticProvider, let uri = documentURI {
                semanticTokens = (try? await provider.semanticTokens(for: uri)) ?? []
            }

            let allTokens = lexicalTokens + structuralTokens + semanticTokens
            guard !allTokens.isEmpty else {
                return highlightDocument(source: source)
            }

            let merged = HighlightMerger.merge(allTokens, sourceByteCount: source.utf8.count)
            let spans = HighlightMerger.resolveToSpans(
                tokens: merged,
                source: source,
                resolver: resolver,
                defaultStyle: theme.defaultStyle
            )

            var scratch = splitScratch
            let result = splitDocumentSpans(
                spans, source: source, defaultStyle: theme.defaultStyle, scratch: &scratch
            )
            return result
        }

        /// The lexical layer: the shared scanners' keyword, string, comment, number, type and attribute tokens,
        /// the baseline the structural and semantic layers refine.
        private func buildLexicalTokens(source: String) -> [HighlightToken] {
            LexicalHighlightEngine().highlight(utf8: Array(source.utf8), language: lexicalLanguage)
        }

        /// The lexical layer alone, resolved to one span array per line.
        private func lexicalLines(source: String) -> [[StyledSpan]] {
            let utf8 = Array(source.utf8)
            return HighlightMerger.resolveToLines(
                tokens: LexicalHighlightEngine().highlight(utf8: utf8, language: lexicalLanguage),
                utf8: utf8, resolver: resolver, defaultStyle: theme.defaultStyle)
        }

        /// Highlights only the visible lines, querying the tree over their byte range; without a usable parse the
        /// lexical engine scans them instead.
        public func highlightViewport(source: String, visibleLineRange: Range<Int>) -> [[StyledSpan]] {
            guard !source.isEmpty else {
                return [[StyledSpan(text: "", style: theme.defaultStyle)]]
            }

            switch strategy {
                case .grammar(let gs):
                    guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                        return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                    }
                    do {
                        let tree = try gs.parseTree(for: source)
                        guard gs.passesQualityGate else {
                            return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                        }

                        let byteRange = lineRangeToByteRange(source: source, lineRange: visibleLineRange)
                        let matches = QueryMatcher.execute(
                            query: gs.query, tree: tree, byteRange: byteRange)
                        let tokens = gs.highlighter.buildTokens(matches: matches, roles: gs.roles, layer: .structural)

                        guard !tokens.isEmpty else {
                            return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                        }

                        let viewportSource = extractViewportSource(
                            source: source, byteRange: byteRange)
                        let vpByteCount = viewportSource.utf8.count
                        let localTokens = tokens.compactMap { token -> HighlightToken? in
                            let start = token.byteRange.lowerBound - byteRange.lowerBound
                            let end = token.byteRange.upperBound - byteRange.lowerBound
                            guard start >= 0, end <= vpByteCount, start < end else { return nil }
                            return HighlightToken(
                                byteRange: start ..< end,
                                role: token.role,
                                modifiers: token.modifiers,
                                layer: token.layer,
                                priority: token.priority
                            )
                        }

                        let merged = HighlightMerger.merge(
                            localTokens, sourceByteCount: viewportSource.utf8.count)
                        let spans = HighlightMerger.resolveToSpans(
                            tokens: merged,
                            source: viewportSource,
                            resolver: resolver,
                            defaultStyle: theme.defaultStyle
                        )

                        var scratch = splitScratch
                        return splitDocumentSpans(
                            spans, source: viewportSource, defaultStyle: theme.defaultStyle,
                            scratch: &scratch)
                    } catch {
                        return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                    }

                case .fallback:
                    return viewportFallback(source: source, visibleLineRange: visibleLineRange)
            }
        }

        /// The three-layer merge restricted to the visible lines, for a first render ahead of
        /// `highlightDocumentMerged(source:)`.
        public func highlightViewportMerged(
            source: String, visibleLineRange: Range<Int>
        ) async -> [[StyledSpan]] {
            guard !source.isEmpty else {
                return [[StyledSpan(text: "", style: theme.defaultStyle)]]
            }

            let byteRange = lineRangeToByteRange(source: source, lineRange: visibleLineRange)
            let viewportSource = extractViewportSource(source: source, byteRange: byteRange)

            // Layer 0: lexical baseline over the visible bytes only
            let lexicalTokens = LexicalHighlightEngine()
                .highlight(
                    utf8: Array(viewportSource.utf8), language: lexicalLanguage)

            // Layer 1: structural tokens scoped to viewport
            var structuralTokens: [HighlightToken] = []
            if case .grammar(let gs) = strategy {
                if source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes {
                    if let tree = try? gs.parseTree(for: source) {
                        if gs.passesQualityGate {
                            let matches = QueryMatcher.execute(
                                query: gs.query, tree: tree, byteRange: byteRange)
                            let vpCount = viewportSource.utf8.count
                            structuralTokens = gs.highlighter
                                .buildTokens(
                                    matches: matches, roles: gs.roles, layer: .structural
                                )
                                .compactMap { token -> HighlightToken? in
                                    let start = token.byteRange.lowerBound - byteRange.lowerBound
                                    let end = token.byteRange.upperBound - byteRange.lowerBound
                                    guard start >= 0, end <= vpCount, start < end else { return nil }
                                    return HighlightToken(
                                        byteRange: start ..< end,
                                        role: token.role, modifiers: token.modifiers,
                                        layer: token.layer, priority: token.priority)
                                }
                        }
                    }
                }
            }

            // Layer 2: semantic tokens from LSP scoped to viewport
            var semanticTokens: [HighlightToken] = []
            if let provider = semanticProvider, let uri = documentURI {
                let allSemantic = (try? await provider.semanticTokens(for: uri)) ?? []
                semanticTokens = allSemantic.compactMap { token in
                    let start = token.byteRange.lowerBound - byteRange.lowerBound
                    let end = token.byteRange.upperBound - byteRange.lowerBound
                    guard start >= 0, end <= viewportSource.utf8.count, start < end else {
                        return nil
                    }
                    return HighlightToken(
                        byteRange: start ..< end, role: token.role,
                        modifiers: token.modifiers, layer: token.layer, priority: token.priority)
                }
            }

            let allTokens = lexicalTokens + structuralTokens + semanticTokens
            guard !allTokens.isEmpty else {
                return lexicalLines(source: viewportSource)
            }

            let merged = HighlightMerger.merge(
                allTokens, sourceByteCount: viewportSource.utf8.count)
            let spans = HighlightMerger.resolveToSpans(
                tokens: merged, source: viewportSource, resolver: resolver,
                defaultStyle: theme.defaultStyle)

            var scratch = splitScratch
            return splitDocumentSpans(
                spans, source: viewportSource, defaultStyle: theme.defaultStyle, scratch: &scratch)
        }

        // MARK: - Viewport Helpers

        private func lineRangeToByteRange(source: String, lineRange: Range<Int>) -> Range<Int> {
            let utf8 = source.utf8
            var lineStarts: [Int] = [0]
            for (i, byte) in utf8.enumerated() where byte == 0x0A {
                lineStarts.append(i + 1)
            }

            let startLine = min(lineRange.lowerBound, lineStarts.count - 1)
            let endLine = min(lineRange.upperBound, lineStarts.count)

            let startByte = lineStarts[max(startLine, 0)]
            let endByte: Int
            if endLine < lineStarts.count {
                endByte = lineStarts[endLine]
            } else {
                endByte = utf8.count
            }

            return startByte ..< endByte
        }

        private func extractViewportSource(source: String, byteRange: Range<Int>) -> String {
            let utf8 = Array(source.utf8)
            let start = max(byteRange.lowerBound, 0)
            let end = min(byteRange.upperBound, utf8.count)
            guard start < end else { return "" }
            return String(decoding: utf8[start ..< end], as: UTF8.self)
        }

        private func extractVisibleLines(source: String, visibleLineRange: Range<Int>) -> [String] {
            let allLines = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let start = max(visibleLineRange.lowerBound, 0)
            let end = min(visibleLineRange.upperBound, allLines.count)
            guard start < end else { return [""] }
            return Array(allLines[start ..< end])
        }

        /// The visible lines through the lexical engine, scanned together so a string or comment that opens
        /// on one visible line and closes on another is styled as one.
        private func viewportFallback(
            source: String, visibleLineRange: Range<Int>
        ) -> [[StyledSpan]] {
            let lines = extractVisibleLines(source: source, visibleLineRange: visibleLineRange)
            return lexicalLines(source: lines.joined(separator: "\n"))
        }

        public func highlightLines<C: Collection>(_ lines: C) -> [[StyledSpan]]
        where C.Element == String {
            highlightJoinedLines(lines.joined(separator: "\n"))
        }

        /// The lines of `text`, split on `\n`, highlighted as ``highlightLines(_:)`` highlights them once joined:
        /// for text a document reads as one run, which splitting into lines first would only copy.
        public func highlightJoinedLines(_ text: String) -> [[StyledSpan]] {
            switch strategy {
                case .fallback:
                    return lexicalLines(source: text)
                case .grammar:
                    return highlightDocument(source: text)
            }
        }
    }

    public static func highlightDocument(
        source: String,
        language: String?,
        theme: Theme = .monokai
    ) -> [[StyledSpan]] {
        let useGrammar = source.utf8.count <= maxGrammarSourceBytes
        return Session(language: language, theme: theme, preferGrammar: useGrammar)
            .highlightDocument(source: source)
    }

    /// One line through the lexical engine alone, with no grammar and no context from neighbouring lines.
    public static func highlightLine(
        _ line: String,
        language: String?,
        theme: Theme = .monokai
    ) -> [StyledSpan] {
        let utf8 = Array(line.utf8)
        let lexicalLanguage = language.flatMap(Language.init(name:)) ?? .plain
        return HighlightMerger.resolveToSpans(
            tokens: LexicalHighlightEngine().highlight(utf8: utf8, language: lexicalLanguage),
            utf8: utf8[...], resolver: RoleBasedThemeResolver(theme: theme), defaultStyle: theme.defaultStyle)
    }

    public static func makeSession(
        language: String?,
        theme: Theme = .monokai,
        preferGrammar: Bool = true
    ) -> Session {
        Session(language: language, theme: theme, preferGrammar: preferGrammar)
    }

    /// The language `filename` maps to, from the runtime registry first and the bundled manifest otherwise.
    public static func detectLanguage(for filename: String) -> String? {
        if let registered = GrammarRegistry.shared.entry(forFilename: filename) {
            return registered.name
        }
        return BundledLanguageManifest.entry(forFilename: filename)?.name
    }

    /// Every language the bundled manifest or the runtime registry names, sorted.
    public static var bundledLanguageNames: [String] {
        let bundled = BundledLanguageManifest.entries.map(\.name)
        let runtime = GrammarRegistry.shared.languageNames
        return Array(Set(bundled).union(runtime)).sorted()
    }

    /// Whether `language` has a grammar and a highlight query: trusted for a runtime registration, checked in the
    /// bundle otherwise.
    public static func hasBundledResources(for language: String) -> Bool {
        if let entry = GrammarRegistry.shared.entry(forLanguage: language) {
            _ = entry
            return true
        }
        guard let entry = BundledLanguageManifest.entry(forLanguage: language) else {
            return false
        }

        let bundle = KittySyntaxResources.bundle
        let subdirectory = "Grammars/\(entry.path)"
        return bundle.url(forResource: "grammar", withExtension: "json", subdirectory: subdirectory)
            != nil
            && bundle.url(
                forResource: "highlights", withExtension: "scm", subdirectory: subdirectory) != nil
    }

    /// Ensures grammar artifacts are loaded for a language, compiling off the main thread.
    /// Returns true if artifacts became available (newly loaded or already cached).
    public static func ensureArtifacts(
        for language: String, taskProvider: any TaskProvider = .default
    ) async -> Bool {
        await taskProvider.detachedTask(role: .work, priority: .userInitiated) {
            await SyntaxArtifactsCache.loadIfNeeded(for: language)
            return SyntaxArtifactsCache.artifacts(for: language) != nil
        }
        .value
    }

    @discardableResult
    public static func prewarmArtifacts<S: Sequence>(for languages: S) async -> Set<String>
    where S.Element == String {
        await SyntaxArtifactsCache.prewarm(languages: languages)
    }
}

private struct SyntaxArtifacts: Sendable {
    let parseTable: ParseTable
    let lexTable: LexTable
    let productions: [ProductionRule]
    let query: Query
    /// The role of each of `query`'s capture names, resolved once per language.
    let roles: CaptureRoles
    let needsExternalScanner: Bool
    let scannerType: (any GrammarExternalScanner.Type)?

    init(
        parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule], query: Query,
        needsExternalScanner: Bool, scannerType: (any GrammarExternalScanner.Type)?
    ) {
        self.parseTable = parseTable
        self.lexTable = lexTable
        self.productions = productions
        self.query = query
        roles = CaptureRoles(captureNames: query.captureNames)
        self.needsExternalScanner = needsExternalScanner
        self.scannerType = scannerType
    }
}

private struct SplitLinesScratch {
    var lines: [[StyledSpan]] = []
}

private enum SyntaxArtifactsCache {
    private static let storage = Mutex([String: SyntaxArtifacts?]())

    static func artifacts(for language: String) -> SyntaxArtifacts? {
        storage.withLock { $0[language] } ?? nil
    }

    static func loadIfNeeded(for language: String) async {
        let alreadyCached: Bool = storage.withLock { $0[language] != nil }
        guard !alreadyCached else { return }

        let loaded = await loadArtifacts(for: language, cachedOnly: false)
        storage.withLock { cache in
            guard !cache.keys.contains(language) else { return }
            cache[language] = loaded
        }
    }

    static func prewarm<S: Sequence>(languages: S) async -> Set<String> where S.Element == String {
        let uniqueLanguages = Set(languages)
        let uncachedLanguages = uniqueLanguages.filter { language in
            storage.withLock { !$0.keys.contains(language) }
        }

        await withTaskGroup(of: (String, SyntaxArtifacts?).self) { group in
            for language in uncachedLanguages {
                group.addTask {
                    (language, await loadArtifacts(for: language, cachedOnly: true))
                }
            }

            for await (language, loadedArtifacts) in group {
                guard let loadedArtifacts else { continue }
                storage.withLock { cache in
                    guard !cache.keys.contains(language) else { return }
                    cache[language] = loadedArtifacts
                }
            }
        }

        return Set(
            uniqueLanguages.filter { language in
                storage.withLock {
                    if case .some(.some(_)) = $0[language] {
                        return true
                    }
                    return false
                }
            })
    }

    private static func loadArtifacts(for language: String, cachedOnly: Bool) async -> SyntaxArtifacts? {
        // A runtime registration wins over the bundled manifest; either way `entry.path` names a `Grammars/` directory.
        let entry: GrammarRegistry.LanguageEntry
        if let registered = GrammarRegistry.shared.entry(forLanguage: language) {
            entry = registered
        } else if let bundled = BundledLanguageManifest.entry(forLanguage: language) {
            entry = GrammarRegistry.LanguageEntry(bundled: bundled)
        } else {
            return nil
        }

        let bundle = KittySyntaxResources.bundle
        guard
            let resourcePath = bundle.resourcePath,
            let queryURL = bundle.url(
                forResource: "highlights",
                withExtension: "scm",
                subdirectory: "Grammars/\(entry.path)"
            )
        else {
            return nil
        }

        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
            let query = try? QueryParser.parse(querySource)
        else {
            return nil
        }

        // Loaded through the registry, whose disk cache spares a relaunch the parse-table compile.
        let grammarsPath = "\(resourcePath)/Grammars"
        let grammar: GrammarDefinition
        do {
            grammar = try GrammarRegistry.shared.grammar(
                for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return nil
        }

        let needsExternals = !grammar.externals.isEmpty
        let scannerType = GrammarRegistry.shared.scannerType(forGrammar: grammar.name)

        // Without its external scanners a grammar can't parse, so a session never reads its table, and compiling one
        // (bash's especially) can take gigabytes: store empty tables and keep the flag for capability reporting.
        if needsExternals && scannerType == nil {
            if cachedOnly { return nil }
            return SyntaxArtifacts(
                parseTable: ParseTable(
                    stateCount: 0, symbols: [], terminals: [], nonTerminals: [],
                    actions: [], gotos: []),
                lexTable: LexTable(),
                productions: [],
                query: query,
                needsExternalScanner: true,
                scannerType: nil
            )
        }

        let compiled: ParseTableCompiler.CompilationResult
        do {
            if cachedOnly {
                guard
                    let stored = try GrammarRegistry.shared.cachedResult(
                        for: entry.name, grammarsPath: grammarsPath)
                else { return nil }
                compiled = stored
            } else {
                compiled = try await GrammarRegistry.shared.compiledResult(
                    for: entry.name, grammarsPath: grammarsPath)
            }
        } catch {
            return nil
        }

        return SyntaxArtifacts(
            parseTable: compiled.parseTable,
            lexTable: compiled.lexTable,
            productions: compiled.productions,
            query: query,
            needsExternalScanner: false,
            scannerType: scannerType
        )
    }
}

private func splitDocumentSpans(
    _ spans: [StyledSpan],
    source: String,
    defaultStyle: Style,
    scratch: inout SplitLinesScratch
) -> [[StyledSpan]] {
    if source.isEmpty {
        return [[StyledSpan(text: "", style: defaultStyle)]]
    }

    scratch.lines.removeAll(keepingCapacity: true)
    scratch.lines.append([])

    for span in spans {
        let text = span.text
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            guard let nlIndex = text[searchStart...].firstIndex(of: "\n") else {
                scratch.lines[scratch.lines.count - 1]
                    .append(
                        StyledSpan(text: String(text[searchStart...]), style: span.style)
                    )
                break
            }
            if nlIndex > searchStart {
                scratch.lines[scratch.lines.count - 1]
                    .append(
                        StyledSpan(text: String(text[searchStart ..< nlIndex]), style: span.style)
                    )
            }
            scratch.lines.append([])
            searchStart = text.index(after: nlIndex)
        }
    }

    if source.last == "\n" {
        scratch.lines.append([])
    }

    return scratch.lines.isEmpty ? [[StyledSpan(text: "", style: defaultStyle)]] : scratch.lines
}
