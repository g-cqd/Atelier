import Foundation
import KittyCodecs
import KittyGrammar
import KittyParser
import KittyQuery
import KittySync

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

            init(artifacts: SyntaxArtifacts, theme: Theme) {
                parser = GrammarParser(
                    parseTable: artifacts.parseTable,
                    lexTable: artifacts.lexTable,
                    productions: artifacts.productions
                )
                query = artifacts.query
                highlighter = Highlighter(theme: theme)
            }
        }

        private let language: String?
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
            switch strategy {
            case .grammar(let grammarSession):
                guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                    return fallbackHighlightDocument(
                        source: source, language: language, theme: theme)
                }
                do {
                    let tree = try grammarSession.parser.parse(source)
                    guard tree.root.type != "_start" else {
                        strategy = .fallback
                        return fallbackHighlightDocument(
                            source: source, language: language, theme: theme)
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
                    return fallbackHighlightDocument(
                        source: source, language: language, theme: theme)
                }

            case .fallback:
                return fallbackHighlightDocument(source: source, language: language, theme: theme)
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
                    let tree = try gs.parser.parse(source)
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

        /// Build lexical-layer tokens from the fallback highlighter.
        /// These provide Tier 1 (keyword/string/comment) highlighting as a baseline
        /// that structural and semantic layers can refine.
        private func buildLexicalTokens(source: String) -> [HighlightToken] {
            let fallbackSpans = fallbackHighlightDocument(
                source: source, language: language, theme: theme)
            var tokens: [HighlightToken] = []
            var byteOffset = 0

            for lineSpans in fallbackSpans {
                for span in lineSpans {
                    let byteLen = span.text.utf8.count
                    guard byteLen > 0 else { continue }
                    let range = byteOffset..<(byteOffset + byteLen)

                    // Only emit tokens for non-default-styled spans
                    if span.style != theme.defaultStyle {
                        let role = inferRoleFromStyle(span.style)
                        tokens.append(HighlightToken(
                            byteRange: range,
                            role: role,
                            layer: .lexical,
                            priority: 0
                        ))
                    }
                    byteOffset += byteLen
                }
                // Account for newline between lines (except after last line)
                byteOffset += 1  // \n
            }

            // Correct for the extra newline added after the last line
            if !fallbackSpans.isEmpty {
                // We added one too many newlines; doesn't affect token ranges since
                // we only emitted tokens for actual span text.
            }

            return tokens
        }

        /// Best-effort role inference from a lexical fallback style by matching
        /// against known theme styles. This is intentionally coarse — lexical
        /// tokens carry less information than structural ones.
        private func inferRoleFromStyle(_ style: Style) -> HighlightRole {
            if style == theme.style(for: "keyword") { return .keyword }
            if style == theme.style(for: "string") { return .string }
            if style == theme.style(for: "comment") { return .comment }
            if style == theme.style(for: "number") { return .number }
            if style == theme.style(for: "type") { return .type }
            if style == theme.style(for: "attribute") { return .attribute }
            if style == theme.style(for: "constant.builtin") { return .constantBuiltin }
            if style == theme.style(for: "string.special.key") { return .stringSpecial }
            return .variable
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
                    let tree = try gs.parser.parse(source)
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
                            byteRange: start..<end,
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

            // Layer 0: lexical baseline for visible lines only
            let visibleLines = extractVisibleLines(
                source: source, visibleLineRange: visibleLineRange)
            let lexicalSpans = visibleLines.map {
                fallbackHighlightLine($0, language: language, theme: theme)
            }
            var lexicalTokens: [HighlightToken] = []
            var byteOffset = 0
            for lineSpans in lexicalSpans {
                for span in lineSpans {
                    let byteLen = span.text.utf8.count
                    guard byteLen > 0 else { continue }
                    if span.style != theme.defaultStyle {
                        let role = inferRoleFromStyle(span.style)
                        lexicalTokens.append(HighlightToken(
                            byteRange: byteOffset..<(byteOffset + byteLen),
                            role: role, layer: .lexical, priority: 0))
                    }
                    byteOffset += byteLen
                }
                byteOffset += 1  // \n
            }

            // Layer 1: structural tokens scoped to viewport
            var structuralTokens: [HighlightToken] = []
            if case .grammar(let gs) = strategy {
                if source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes {
                    if let tree = try? gs.parser.parse(source) {
                        if tree.root.type != "_start" {
                            let matches = QueryMatcher.execute(
                                query: gs.query, tree: tree, byteRange: byteRange)
                            let vpCount = viewportSource.utf8.count
                            structuralTokens = gs.highlighter.buildTokens(
                                matches: matches, layer: .structural
                            ).compactMap { token -> HighlightToken? in
                                let start = token.byteRange.lowerBound - byteRange.lowerBound
                                let end = token.byteRange.upperBound - byteRange.lowerBound
                                guard start >= 0, end <= vpCount, start < end else { return nil }
                                return HighlightToken(
                                    byteRange: start..<end,
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
                        byteRange: start..<end, role: token.role,
                        modifiers: token.modifiers, layer: token.layer, priority: token.priority)
                }
            }

            let allTokens = lexicalTokens + structuralTokens + semanticTokens
            guard !allTokens.isEmpty else {
                return lexicalSpans
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

            return startByte..<endByte
        }

        private func extractViewportSource(source: String, byteRange: Range<Int>) -> String {
            let utf8 = Array(source.utf8)
            let start = max(byteRange.lowerBound, 0)
            let end = min(byteRange.upperBound, utf8.count)
            guard start < end else { return "" }
            return String(decoding: utf8[start..<end], as: UTF8.self)
        }

        private func extractVisibleLines(source: String, visibleLineRange: Range<Int>) -> [String] {
            let allLines = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let start = max(visibleLineRange.lowerBound, 0)
            let end = min(visibleLineRange.upperBound, allLines.count)
            guard start < end else { return [""] }
            return Array(allLines[start..<end])
        }

        private func viewportFallback(
            source: String, visibleLineRange: Range<Int>
        ) -> [[StyledSpan]] {
            let lines = extractVisibleLines(source: source, visibleLineRange: visibleLineRange)
            return lines.map { fallbackHighlightLine($0, language: language, theme: theme) }
        }

        public func highlightLines<C: Collection>(_ lines: C) -> [[StyledSpan]]
        where C.Element == String {
            switch strategy {
            case .fallback:
                if lines.isEmpty {
                    return [fallbackHighlightLine("", language: language, theme: theme)]
                }
                return lines.map { fallbackHighlightLine($0, language: language, theme: theme) }
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

    public static func highlightLine(
        _ line: String,
        language: String?,
        theme: Theme = .monokai
    ) -> [StyledSpan] {
        fallbackHighlightLine(line, language: language, theme: theme)
    }

    public static func makeSession(
        language: String?,
        theme: Theme = .monokai,
        preferGrammar: Bool = true
    ) -> Session {
        Session(language: language, theme: theme, preferGrammar: preferGrammar)
    }

    public static func detectLanguage(for filename: String) -> String? {
        BundledLanguageManifest.entry(forFilename: filename)?.name
    }

    public static var bundledLanguageNames: [String] {
        BundledLanguageManifest.entries.map(\.name)
    }

    public static func hasBundledResources(for language: String) -> Bool {
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
    public static func ensureArtifacts(for language: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            SyntaxArtifactsCache.loadIfNeeded(for: language)
            return SyntaxArtifactsCache.artifacts(for: language) != nil
        }.value
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
    private static let storage = StateLock(initialState: [String: SyntaxArtifacts?]())

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
        guard let entry = BundledLanguageManifest.entry(forLanguage: language) else {
            return nil
        }

        let bundle = KittySyntaxResources.bundle
        guard
            let grammarURL = bundle.url(
                forResource: "grammar",
                withExtension: "json",
                subdirectory: "Grammars/\(entry.path)"
            ),
            let queryURL = bundle.url(
                forResource: "highlights",
                withExtension: "scm",
                subdirectory: "Grammars/\(entry.path)"
            )
        else {
            return nil
        }

        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
            let grammar = try? GrammarLoader.load(from: grammarURL.path),
            let query = try? QueryParser.parse(querySource)
        else {
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

        guard let compiled = try? ParseTableCompiler.compile(grammar) else {
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
            if let nlIndex = text[searchStart...].firstIndex(of: "\n") {
                if nlIndex > searchStart {
                    scratch.lines[scratch.lines.count - 1].append(
                        StyledSpan(text: String(text[searchStart..<nlIndex]), style: span.style)
                    )
                }
                scratch.lines.append([])
                searchStart = text.index(after: nlIndex)
            } else {
                scratch.lines[scratch.lines.count - 1].append(
                    StyledSpan(text: String(text[searchStart...]), style: span.style)
                )
                break
            }
        }
    }

    if source.last == "\n" {
        scratch.lines.append([])
    }

    return scratch.lines.isEmpty ? [[StyledSpan(text: "", style: defaultStyle)]] : scratch.lines
}

private enum HighlightLexicon {
    static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return",
        "import", "from", "as", "is", "in", "not", "and", "or",
        "with", "try", "except", "finally", "raise", "pass", "break",
        "continue", "yield", "lambda", "global", "nonlocal", "assert",
        "del", "True", "False", "None", "true", "false", "null", "nil",
        "async", "await", "self", "then", "fi", "done", "esac", "function",
        "local", "export", "source", "end", "elsif", "unless", "module",
        "begin", "rescue", "alias", "undef", "repeat", "until",
    ]
    static let pythonTypes: Set<String> = [
        "int", "float", "str", "bool", "list", "dict", "tuple",
        "set", "bytes", "type", "object", "range", "table",
    ]
    static let javaScriptKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "for", "while",
        "return", "class", "new", "this", "import", "export", "from",
        "default", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "typeof", "instanceof", "in", "of", "async",
        "await", "yield", "void", "delete", "extends", "implements",
        "interface", "type", "enum", "abstract", "static", "public",
        "private", "protected", "readonly", "override", "struct",
        "typedef", "union", "goto", "sizeof", "volatile", "inline",
        "package", "func", "go", "defer", "select", "chan", "range",
        "map", "trait", "impl", "match", "mut", "pub", "crate", "where",
        "macro_rules", "unsafe", "extern", "sealed", "record", "when",
        "companion", "object", "val",
    ]
    static let javaScriptTypes: Set<String> = [
        "string", "number", "boolean", "any", "void", "never",
        "unknown", "undefined", "null", "Array", "Promise", "Map", "Set",
        "int", "char", "float", "double", "long", "short", "byte",
        "bool", "usize", "isize", "u8", "u16", "u32", "u64", "i8", "i16",
        "i32", "i64", "String", "Vec", "Result", "Option",
    ]
    static let swiftKeywords: Set<String> = [
        "import", "struct", "class", "enum", "func", "var", "let", "guard", "if", "else", "switch",
        "case", "return", "default",
        "final", "extension", "public", "private", "static", "mutating", "override", "init",
        "deinit", "typealias", "where", "while", "for",
        "in", "do", "catch", "try", "throw", "throws", "as", "is", "self", "nil", "true", "false",
        "protocol", "associatedtype",
        "internal", "fileprivate", "open", "weak", "unowned", "lazy", "async", "await", "some",
        "any", "defer", "break", "continue",
        "fallthrough", "repeat", "super", "inout", "convenience", "required", "dynamic", "optional",
        "indirect", "nonisolated",
        "consuming", "borrowing", "@MainActor", "@Sendable", "@escaping", "@autoclosure",
        "@discardableResult",
    ]
    static let swiftTypes: Set<String> = [
        "String", "Int", "Bool", "Double", "Float", "Any", "Array", "Dictionary", "Optional",
        "UInt32", "UInt8", "UInt16", "UInt64",
        "UInt", "Int8", "Int16", "Int32", "Int64", "Date", "Data", "URL", "Error", "Result", "Void",
        "Never", "Character",
        "Substring", "Set", "ClosedRange", "Range", "Comparable", "Equatable", "Hashable",
        "Codable", "Decodable", "Encodable",
        "Sendable", "Identifiable", "CustomStringConvertible", "View", "Task", "AsyncStream",
        "MainActor",
    ]
}

private func fallbackHighlightDocument(source: String, language: String?, theme: Theme)
    -> [[StyledSpan]] {
    let lines =
        source.isEmpty
        ? [""] : source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return lines.map { fallbackHighlightLine($0, language: language, theme: theme) }
}

private func fallbackHighlightLine(_ line: String, language: String?, theme: Theme) -> [StyledSpan] {
    switch language {
    case "json":
        return fallbackHighlightJSON(line, theme: theme)
    case "python", "bash", "ruby", "lua", "toml", "yaml":
        return fallbackHighlightPython(line, theme: theme)
    case "javascript", "typescript", "c", "cpp", "css", "go", "java", "kotlin", "rust":
        return fallbackHighlightJavaScript(line, theme: theme)
    case "swift":
        return fallbackHighlightSwift(line, theme: theme)
    default:
        return fallbackHighlightGeneric(line, theme: theme)
    }
}

private func fallbackHighlightJSON(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let keyStyle = theme.style(for: "string.special.key")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")
    let constantStyle = theme.style(for: "constant.builtin")

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0

    while index < chars.count {
        let char = chars[index]

        if char == "\"" {
            var token = "\""
            index += 1
            while index < chars.count && chars[index] != "\"" {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append("\"")
                index += 1
            }
            var peek = index
            while peek < chars.count && chars[peek] == " " { peek += 1 }
            let isKey = peek < chars.count && chars[peek] == ":"
            spans.append(StyledSpan(text: token, style: isKey ? keyStyle : stringStyle))
        } else if char.isNumber
            || (char == "-" && index + 1 < chars.count && chars[index + 1].isNumber)
        {
            var token = String(char)
            index += 1
            while index < chars.count
                && (chars[index].isNumber || chars[index] == "." || chars[index] == "e"
                    || chars[index] == "E" || chars[index] == "+" || chars[index] == "-") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))
        } else if chars[index...].starts(with: "true".unicodeScalars.map(Character.init))
            || chars[index...].starts(with: "false".unicodeScalars.map(Character.init))
            || chars[index...].starts(with: "null".unicodeScalars.map(Character.init)) {
            let keyword = chars[index...].prefix(while: { $0.isLetter })
            let token = String(keyword)
            spans.append(StyledSpan(text: token, style: constantStyle))
            index += token.count
        } else {
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    return spans
}

private func fallbackHighlightPython(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let keywordStyle = theme.style(for: "keyword")
    let typeStyle = theme.style(for: "type")
    let commentStyle = theme.style(for: "comment")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0
    var current = ""

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if HighlightLexicon.pythonKeywords.contains(current) {
            style = keywordStyle
        } else if HighlightLexicon.pythonTypes.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
            let first = current.first, first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        if char == "#" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "\"" || char == "'" {
            flushCurrent()
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))
        } else if char.isLetter || char == "_" {
            current.append(char)
            index += 1
        } else if char.isNumber && current.isEmpty {
            var token = String(char)
            index += 1
            while index < chars.count
                && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))
        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        } else {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    flushCurrent()
    return spans
}

private func fallbackHighlightJavaScript(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let keywordStyle = theme.style(for: "keyword")
    let typeStyle = theme.style(for: "type")
    let commentStyle = theme.style(for: "comment")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0
    var current = ""

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if HighlightLexicon.javaScriptKeywords.contains(current) {
            style = keywordStyle
        } else if HighlightLexicon.javaScriptTypes.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
            let first = current.first, first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "/" && index + 1 < chars.count && chars[index + 1] == "*" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "\"" || char == "'" || char == "`" {
            flushCurrent()
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))
        } else if char.isLetter || char == "_" || char == "$" {
            current.append(char)
            index += 1
        } else if char.isNumber && current.isEmpty {
            var token = String(char)
            index += 1
            while index < chars.count
                && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))
        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        } else {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    flushCurrent()
    return spans
}

private func fallbackHighlightGeneric(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let commentStyle = theme.style(for: "comment")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0

    while index < chars.count {
        let char = chars[index]

        if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "#" {
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "\"" || char == "'" {
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))
        } else if char.isNumber {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == ".") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))
        } else {
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    return spans
}

private func fallbackHighlightSwift(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let keywordStyle = theme.style(for: "keyword")
    let typeStyle = theme.style(for: "type")
    let commentStyle = theme.style(for: "comment")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")
    let attrStyle = theme.style(for: "attribute")

    var spans: [StyledSpan] = []
    var current = ""
    let chars = Array(line)
    var index = 0

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if current.hasPrefix("@") && HighlightLexicon.swiftKeywords.contains(current) {
            style = attrStyle
        } else if HighlightLexicon.swiftKeywords.contains(current) {
            style = keywordStyle
        } else if HighlightLexicon.swiftTypes.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
            let first = current.first, first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "/" && index + 1 < chars.count && chars[index + 1] == "*" {
            flushCurrent()
            var token = "/*"
            index += 2
            while index + 1 < chars.count {
                if chars[index] == "*" && chars[index + 1] == "/" {
                    token.append("*/")
                    index += 2
                    break
                }
                token.append(chars[index])
                index += 1
            }
            if index < chars.count && !token.hasSuffix("*/") {
                token.append(contentsOf: chars[index...])
                index = chars.count
            }
            spans.append(StyledSpan(text: token, style: commentStyle))
        } else if char == "@" {
            flushCurrent()
            current = "@"
            index += 1
            while index < chars.count
                && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
                current.append(chars[index])
                index += 1
            }
            flushCurrent()
        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        } else if char == "\"" {
            flushCurrent()
            var token = "\""
            index += 1
            while index < chars.count && chars[index] != "\"" {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append("\"")
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))
        } else {
            current.append(char)
            index += 1
        }
    }

    flushCurrent()
    return spans
}
