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

/// Signpost emitter for syntax-highlighter hot paths. Audit D10 —
/// mirrors `RenderPipeline.swift` / `EditorStateCore.swift` so Instruments
/// can attribute frame-budget time to grammar parsing, token merging,
/// and viewport vs full-document highlights.
private let highlighterSignposter = OSSignposter(
    subsystem: "com.kittytui.syntax", category: "highlight")

public enum LanguageHighlighter: Sendable {
    /// Maximum source size in bytes for grammar-backed highlighting.
    /// Beyond this, the session falls back to the lightweight lexical highlighter
    /// to prevent runaway memory from per-byte style arrays and token lists.
    public static let maxGrammarSourceBytes = 512_000  // 512 KB

    public final class Session {
        private enum Strategy {
            case grammar(GrammarSession)
            case fallback
        }

        private final class GrammarSession {
            let parser: GrammarParser
            let query: Query
            let highlighter: Highlighter
            let scratch = HighlightScratch()
            /// Cache of the most recently parsed `source` and its tree. Lets
            /// `parseTree(for:)` short-circuit when the document hasn't
            /// changed since the last parse — common during undo/redo
            /// navigation, viewport scroll, and identical reflows after
            /// `bufferingNewest(1)` coalesces a typing burst. Mismatching
            /// the source falls through to a full re-parse.
            var lastParsedSourceHash: Int?
            var lastParsedTree: SyntaxTree?

            init(artifacts: SyntaxArtifacts, theme: Theme) {
                parser = GrammarParser(
                    parseTable: artifacts.parseTable,
                    lexTable: artifacts.lexTable,
                    productions: artifacts.productions
                )
                query = artifacts.query
                highlighter = Highlighter(theme: theme)
            }

            /// Returns a parsed tree for `source`, reusing the previous parse
            /// if `source.hashValue` matches the cached fingerprint. The
            /// hash is `Hasher`-based so collisions across distinct source
            /// strings are vanishingly improbable in practice; an additional
            /// `source.utf8.count` comparison guards the cache against the
            /// pathological case.
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
                let tree = try parser.parse(source)
                lastParsedSourceHash = sourceHash
                lastParsedTree = tree
                return tree
            }
        }

        private let language: String?
        /// The language the shared lexical engine scans for `language`; plain text yields no lexical tokens.
        private let lexicalLanguage: Language
        private let theme: Theme
        private var strategy: Strategy
        private var splitScratch = SplitLinesScratch()

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

        public var isGrammarBacked: Bool {
            if case .grammar = strategy {
                return true
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
            switch strategy {
                case .grammar(let grammarSession):
                    guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                        return lexicalLines(source: source)
                    }
                    do {
                        let tree = try grammarSession.parseTree(for: source)
                        guard tree.root.type != "_start" else {
                            strategy = .fallback
                            return lexicalLines(source: source)
                        }
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
                    } catch {
                        return lexicalLines(source: source)
                    }

                case .fallback:
                    return lexicalLines(source: source)
            }
        }

        /// Produce intermediate `HighlightToken`s preserving semantic roles.
        /// Tokens can later be merged with semantic tokens and resolved to styles.
        public func highlightDocumentTokens(source: String) -> [HighlightToken] {
            switch strategy {
                case .grammar(let gs):
                    guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                        return []
                    }
                    do {
                        let tree = try gs.parseTree(for: source)
                        guard tree.root.type != "_start" else {
                            return []
                        }
                        let matches = QueryMatcher.execute(query: gs.query, tree: tree)
                        return gs.highlighter.buildTokens(matches: matches, layer: .structural)
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
            let resolver = RoleBasedThemeResolver(theme: theme)
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
                utf8: utf8, resolver: RoleBasedThemeResolver(theme: theme), defaultStyle: theme.defaultStyle)
        }

        /// Highlight only the visible viewport lines for fast initial render.
        /// Converts a line range to a byte range and uses scoped query execution.
        /// Falls back to line-by-line lexical highlighting for non-grammar sessions.
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
                        guard tree.root.type != "_start" else {
                            return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                        }

                        let byteRange = lineRangeToByteRange(source: source, lineRange: visibleLineRange)
                        let matches = QueryMatcher.execute(
                            query: gs.query, tree: tree, byteRange: byteRange)
                        let tokens = gs.highlighter.buildTokens(matches: matches, layer: .structural)

                        guard !tokens.isEmpty else {
                            return viewportFallback(source: source, visibleLineRange: visibleLineRange)
                        }

                        let resolver = RoleBasedThemeResolver(theme: theme)
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

        /// Viewport-scoped three-layer merge highlighting.
        /// Returns styled spans for only the visible range; caller should run
        /// full-document `highlightDocumentMerged` in background after this returns.
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
                        if tree.root.type != "_start" {
                            let matches = QueryMatcher.execute(
                                query: gs.query, tree: tree, byteRange: byteRange)
                            let vpCount = viewportSource.utf8.count
                            structuralTokens = gs.highlighter
                                .buildTokens(
                                    matches: matches, layer: .structural
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
            let resolver = RoleBasedThemeResolver(theme: theme)
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
            switch strategy {
                case .fallback:
                    return lexicalLines(source: lines.joined(separator: "\n"))
                case .grammar:
                    let source = lines.isEmpty ? "" : lines.joined(separator: "\n")
                    return highlightDocument(source: source)
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

    public static func detectLanguage(for filename: String) -> String? {
        // Audit A.4/F10 — consult the runtime registry first so ADR 8
        // extension hosts that register additional grammars get their
        // language detected on file open. Bundled is the fallback.
        if let registered = GrammarRegistry.shared.entry(forFilename: filename) {
            return registered.name
        }
        return BundledLanguageManifest.entry(forFilename: filename)?.name
    }

    public static var bundledLanguageNames: [String] {
        // Audit A.4 — union the runtime registry with the bundled manifest
        // so the UI's "what languages do we support" surface reflects
        // any ADR 8 extension contributions, not just the shipped set.
        let bundled = BundledLanguageManifest.entries.map(\.name)
        let runtime = GrammarRegistry.shared.languageNames
        return Array(Set(bundled).union(runtime)).sorted()
    }

    public static func hasBundledResources(for language: String) -> Bool {
        // Audit A.4 — a runtime-registered language with a resource path
        // outside the bundled manifest still counts as "has resources"
        // (its grammar/highlights live wherever the extension host
        // serves them). Try the runtime registry first; fall back to
        // checking the bundled resource layout.
        if let entry = GrammarRegistry.shared.entry(forLanguage: language) {
            // Runtime entry: trust the registration. The extension host
            // is responsible for ensuring its `entry.path` resolves.
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
            SyntaxArtifactsCache.loadIfNeeded(for: language)
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
    let needsExternalScanner: Bool
}

private struct SplitLinesScratch {
    var lines: [[StyledSpan]] = []
}

private enum SyntaxArtifactsCache {
    private static let storage = Mutex([String: SyntaxArtifacts?]())

    static func artifacts(for language: String) -> SyntaxArtifacts? {
        storage.withLock { $0[language] } ?? nil
    }

    static func loadIfNeeded(for language: String) {
        let alreadyCached: Bool = storage.withLock { $0[language] != nil }
        guard !alreadyCached else { return }

        let loaded = loadArtifacts(for: language)
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
                    (language, loadArtifacts(for: language))
                }
            }

            for await (language, loadedArtifacts) in group {
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

    private static func loadArtifacts(for language: String) -> SyntaxArtifacts? {
        // Audit D1 — the registry is the primary dispatch path so
        // ADR 8 extensions can register additional languages; the
        // bundled manifest is the default source for the languages
        // that ship with the binary. `entry.path` is treated as a
        // bundle-relative `Grammars/<path>` directory either way.
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

        // Audit B.6/E1 — route the grammar load + parse-table compile
        // through `GrammarRegistry.shared` instead of compiling
        // in-process every launch. The registry's three-tier cache
        // (in-memory → on-disk `$TMPDIR/kittycode-cache/*.ptable` →
        // fresh compile) amortises the cold-start cost across launches
        // of the same kittycode version. The needsExternals check still
        // gates the compile so bash et al. never trigger the LR(1)
        // item-set expansion the prior comment warned about.
        let grammarsPath = "\(resourcePath)/Grammars"
        let grammar: GrammarDefinition
        do {
            grammar = try GrammarRegistry.shared.grammar(
                for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return nil
        }

        let needsExternals = !grammar.externals.isEmpty

        // Grammars that require external scanners (e.g. bash here-docs,
        // markdown line-break states) cannot produce correct parse trees
        // until a concrete scanner is registered. Session always falls back
        // to lexical highlighting in that case, so the compiled parse
        // table would never be consulted — and the LR(1) item-set
        // expansion for richer grammars (bash in particular) can grow into
        // gigabytes of RAM before hitting the limit guards. Skip the
        // compile entirely for externals grammars and store empty
        // placeholder tables; capability reporting still sees the
        // `needsExternalScanner` flag.
        if needsExternals {
            return SyntaxArtifacts(
                parseTable: ParseTable(
                    stateCount: 0, symbols: [], terminals: [], nonTerminals: [],
                    actions: [], gotos: []),
                lexTable: LexTable(),
                productions: [],
                query: query,
                needsExternalScanner: true
            )
        }

        let compiled: ParseTableCompiler.CompilationResult
        do {
            compiled = try GrammarRegistry.shared.compiledResult(
                for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return nil
        }

        return SyntaxArtifacts(
            parseTable: compiled.parseTable,
            lexTable: compiled.lexTable,
            productions: compiled.productions,
            query: query,
            needsExternalScanner: false
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
