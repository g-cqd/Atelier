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
    public static let maxGrammarSourceBytes = 512_000 // 512 KB

    public final class Session {
        private enum Strategy {
            case grammar(GrammarSession)
            case fallback
        }

        private final class GrammarSession {
            let parser: IncrementalParser
            let query: Query
            let highlighter: Highlighter
            let scratch = HighlightScratch()
            var previousTree: SyntaxTree?

            init(artifacts: SyntaxArtifacts, theme: Theme) {
                parser = IncrementalParser(
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
               let artifacts = SyntaxArtifactsCache.artifacts(for: language) {
                strategy = .grammar(GrammarSession(artifacts: artifacts, theme: theme))
            } else {
                strategy = .fallback
            }
        }

        public func highlightDocument(source: String) -> [[StyledSpan]] {
            switch strategy {
            case .grammar(let grammarSession):
                guard source.utf8.count <= LanguageHighlighter.maxGrammarSourceBytes else {
                    return fallbackHighlightDocument(source: source, language: language, theme: theme)
                }
                do {
                    let tree = try grammarSession.parser.parse(source, oldTree: grammarSession.previousTree)
                    guard tree.root.type != "_start" else {
                        grammarSession.previousTree = nil
                        strategy = .fallback
                        return fallbackHighlightDocument(source: source, language: language, theme: theme)
                    }
                    grammarSession.previousTree = tree
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
                    return fallbackHighlightDocument(source: source, language: language, theme: theme)
                }

            case .fallback:
                return fallbackHighlightDocument(source: source, language: language, theme: theme)
            }
        }

        public func highlightLines<C: Collection>(_ lines: C) -> [[StyledSpan]] where C.Element == String {
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
        return Session(language: language, theme: theme, preferGrammar: useGrammar).highlightDocument(source: source)
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
        return bundle.url(forResource: "grammar", withExtension: "json", subdirectory: subdirectory) != nil &&
            bundle.url(forResource: "highlights", withExtension: "scm", subdirectory: subdirectory) != nil
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
    public static func prewarmArtifacts<S: Sequence>(for languages: S) async -> Set<String> where S.Element == String {
        await SyntaxArtifactsCache.prewarm(languages: languages)
    }
}

private struct SyntaxArtifacts: Sendable {
    let parseTable: ParseTable
    let lexTable: LexTable
    let productions: [ProductionRule]
    let query: Query
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

        return Set(uniqueLanguages.filter { language in
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
        guard let grammarURL = bundle.url(
            forResource: "grammar",
            withExtension: "json",
            subdirectory: "Grammars/\(entry.path)"
        ), let queryURL = bundle.url(
            forResource: "highlights",
            withExtension: "scm",
            subdirectory: "Grammars/\(entry.path)"
        ) else {
            return nil
        }

        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
              let grammar = try? GrammarLoader.load(from: grammarURL.path),
              grammar.externals.isEmpty,
              let compiled = try? ParseTableCompiler.compile(grammar),
              let query = try? QueryParser.parse(querySource)
        else {
            return nil
        }

        return SyntaxArtifacts(
            parseTable: compiled.parseTable,
            lexTable: compiled.lexTable,
            productions: compiled.productions,
            query: query
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
        "import", "struct", "class", "enum", "func", "var", "let", "guard", "if", "else", "switch", "case", "return", "default",
        "final", "extension", "public", "private", "static", "mutating", "override", "init", "deinit", "typealias", "where", "while", "for",
        "in", "do", "catch", "try", "throw", "throws", "as", "is", "self", "nil", "true", "false", "protocol", "associatedtype",
        "internal", "fileprivate", "open", "weak", "unowned", "lazy", "async", "await", "some", "any", "defer", "break", "continue",
        "fallthrough", "repeat", "super", "inout", "convenience", "required", "dynamic", "optional", "indirect", "nonisolated",
        "consuming", "borrowing", "@MainActor", "@Sendable", "@escaping", "@autoclosure", "@discardableResult",
    ]
    static let swiftTypes: Set<String> = [
        "String", "Int", "Bool", "Double", "Float", "Any", "Array", "Dictionary", "Optional", "UInt32", "UInt8", "UInt16", "UInt64",
        "UInt", "Int8", "Int16", "Int32", "Int64", "Date", "Data", "URL", "Error", "Result", "Void", "Never", "Character",
        "Substring", "Set", "ClosedRange", "Range", "Comparable", "Equatable", "Hashable", "Codable", "Decodable", "Encodable",
        "Sendable", "Identifiable", "CustomStringConvertible", "View", "Task", "AsyncStream", "MainActor",
    ]
}

private func fallbackHighlightDocument(source: String, language: String?, theme: Theme) -> [[StyledSpan]] {
    let lines = source.isEmpty ? [""] : source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
        } else if char.isNumber || (char == "-" && index + 1 < chars.count && chars[index + 1].isNumber) {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "e"
                || chars[index] == "E" || chars[index] == "+" || chars[index] == "-")
            {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))
        } else if chars[index...].starts(with: "true".unicodeScalars.map(Character.init))
            || chars[index...].starts(with: "false".unicodeScalars.map(Character.init))
            || chars[index...].starts(with: "null".unicodeScalars.map(Character.init))
        {
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
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }), let first = current.first, first.isNumber {
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
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
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
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }), let first = current.first, first.isNumber {
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
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
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
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }), let first = current.first, first.isNumber {
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
            while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
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
