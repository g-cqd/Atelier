import Foundation
import KittyCodecs
import KittyGrammar
import KittyParser
import KittyQuery
import KittySync

public enum LanguageHighlighter: Sendable {
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
        private let strategy: Strategy
        private var splitScratch = SplitLinesScratch()

        public var prefersLineInput: Bool {
            if case .fallback = strategy {
                return true
            }
            return false
        }

        public init(language: String?, theme: Theme = .monokai) {
            self.language = language
            self.theme = theme

            if let language, let artifacts = SyntaxArtifactsCache.artifacts(for: language) {
                strategy = .grammar(GrammarSession(artifacts: artifacts, theme: theme))
            } else {
                strategy = .fallback
            }
        }

        public func highlightDocument(source: String) -> [[StyledSpan]] {
            switch strategy {
            case .grammar(let grammarSession):
                do {
                    let tree = try grammarSession.parser.parse(source, oldTree: grammarSession.previousTree)
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

        public func highlightLines(_ lines: [String]) -> [[StyledSpan]] {
            let normalizedLines = lines.isEmpty ? [""] : lines

            switch strategy {
            case .fallback:
                return normalizedLines.map { fallbackHighlightLine($0, language: language, theme: theme) }
            case .grammar:
                return highlightDocument(source: normalizedLines.joined(separator: "\n"))
            }
        }
    }

    public static func highlightDocument(
        source: String,
        language: String?,
        theme: Theme = .monokai
    ) -> [[StyledSpan]] {
        Session(language: language, theme: theme).highlightDocument(source: source)
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
        theme: Theme = .monokai
    ) -> Session {
        Session(language: language, theme: theme)
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
        if let cached = storage.withLock({ $0[language] }) {
            return cached
        }

        let loaded = loadArtifacts(for: language)
        storage.withLock { $0[language] = loaded }
        return loaded
    }

    private static func loadArtifacts(for language: String) -> SyntaxArtifacts? {
        let bundle = KittySyntaxResources.bundle
        guard let grammarURL = bundle.url(
            forResource: "grammar",
            withExtension: "json",
            subdirectory: "Grammars/\(language)"
        ), let queryURL = bundle.url(
            forResource: "highlights",
            withExtension: "scm",
            subdirectory: "Grammars/\(language)"
        ) else {
            return nil
        }

        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
              let grammar = try? GrammarLoader.load(from: grammarURL.path),
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
        var current = ""
        for char in span.text {
            if char == "\n" {
                if !current.isEmpty {
                    scratch.lines[scratch.lines.count - 1].append(StyledSpan(text: current, style: span.style))
                    current.removeAll(keepingCapacity: true)
                }
                scratch.lines.append([])
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            scratch.lines[scratch.lines.count - 1].append(StyledSpan(text: current, style: span.style))
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
        "del", "True", "False", "None", "async", "await", "self",
    ]
    static let pythonTypes: Set<String> = [
        "int", "float", "str", "bool", "list", "dict", "tuple",
        "set", "bytes", "type", "object", "range",
    ]
    static let javaScriptKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "for", "while",
        "return", "class", "new", "this", "import", "export", "from",
        "default", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "typeof", "instanceof", "in", "of", "async",
        "await", "yield", "void", "delete", "extends", "implements",
        "interface", "type", "enum", "abstract", "static", "public",
        "private", "protected", "readonly", "override",
    ]
    static let javaScriptTypes: Set<String> = [
        "string", "number", "boolean", "any", "void", "never",
        "unknown", "undefined", "null", "Array", "Promise", "Map", "Set",
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
    case "python":
        return fallbackHighlightPython(line, theme: theme)
    case "javascript", "typescript":
        return fallbackHighlightJavaScript(line, theme: theme)
    case "swift":
        return fallbackHighlightSwift(line, theme: theme)
    default:
        return fallbackHighlightGeneric(line, theme: theme)
    }
}

private func fallbackHighlightJSON(_ line: String, theme: Theme) -> [StyledSpan] {
    let defaultStyle = theme.defaultStyle
    let keywordStyle = theme.style(for: "keyword")
    let stringStyle = theme.style(for: "string")
    let numberStyle = theme.style(for: "number")

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
            spans.append(StyledSpan(text: token, style: isKey ? keywordStyle : stringStyle))
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
            spans.append(StyledSpan(text: token, style: keywordStyle))
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

        if char == "@" {
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
        } else if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
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
