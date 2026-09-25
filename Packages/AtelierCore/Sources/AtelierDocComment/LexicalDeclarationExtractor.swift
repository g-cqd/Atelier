import AtelierLexers
public import AtelierSyntaxModel

/// Documented declarations read without a parser (HOVER-16 phase 4, path b): the lexical scanner finds the comments
/// and strings, a doc comment is the run of comments that ends on the line right above a declaration, and a table per
/// language recognises that declaration's head.
///
/// - TypeScript and JavaScript: `function name`, `class Name`, `interface Name`, `type Name =`, `enum Name`,
///   `namespace Name`, `const|let|var name`, behind any of `export`, `default`, `declare`, `async` and `abstract`;
///   inside a class or interface body, methods, `constructor`, accessors and fields; inside an enum, its members.
/// - Go: `func name`, `func (receiver) name`, `type Name`, `const name` and `var name`, and the names of a grouped
///   `const (…)`, `var (…)` or `type (…)`.
///
/// Known misses, which a grammar's declarations will fix: a JavaScript regular expression holding a quote or a
/// backtick, which the scanner reads as a string opening; a declaration no head names, such as an object literal's
/// method or a computed name; and whatever a macro or a code generator writes.
public struct LexicalDeclarationExtractor: DeclarationExtracting {
    public init() {}

    /// Whether the extractor reads `language`: TypeScript, JavaScript and Go.
    public static func supports(_ language: Language) -> Bool {
        DocCommentConvention.convention(for: language) != nil
    }

    /// - Complexity: O(bytes of `text`), with one lexical scan.
    public func declarations(in text: String, language: Language) -> [SyntaxDeclaration] {
        guard let convention = DocCommentConvention.convention(for: language) else { return [] }
        let source = Source(text: text, language: language)
        let comments = source.docComments(convention: convention)
        let contexts = source.contexts(at: comments.map(\.headStart))
        var declarations: [SyntaxDeclaration] = []
        for (comment, context) in zip(comments, contexts) {
            guard let documentation = convention.markdown(fromComment: source.text(comment.range)[...]) else {
                continue
            }
            let head = source.head(from: comment.headStart)
            for (name, kind, signature) in HeadReader.read(
                head.words, language: language, context: context, signature: source.signature(head))
            {
                declarations.append(
                    SyntaxDeclaration(
                        name: name, kind: kind, range: comment.headStart ..< head.end, documentation: documentation,
                        signature: signature))
            }
        }
        return declarations
    }
}

/// Where a declaration's head sits: at the top level, or inside a body whose members it declares.
enum HeadContext: Equatable {
    case topLevel
    /// A class or interface body.
    case classBody
    case enumBody
    /// A Go `const (…)`, `var (…)` or `type (…)` group, with its keyword.
    case goGroup(String)
}

/// One word or punctuation of a declaration head; a string or a comment reads as one ``literal``.
enum HeadWord: Equatable {
    case identifier(String)
    case punctuation(UInt8)
    case literal
}

/// A text's bytes and what the lexical scanner found in them.
private struct Source {
    let bytes: [UInt8]
    /// Every comment token's range, in order.
    let comments: [Range<Int>]
    /// Whether each byte lies in a comment or a string.
    let masked: [Bool]
    let language: Language

    init(text: String, language: Language) {
        bytes = Array(text.utf8)
        self.language = language
        let tokens = LexicalHighlightEngine().highlight(utf8: bytes, language: language)
        var masked = [Bool](repeating: false, count: bytes.count)
        var comments: [Range<Int>] = []
        for token in tokens where token.role == .comment || token.role == .string {
            let range = token.byteRange.clamped(to: 0 ..< bytes.count)
            for index in range { masked[index] = true }
            if token.role == .comment { comments.append(range) }
        }
        self.masked = masked
        self.comments = comments.sorted { $0.lowerBound < $1.lowerBound }
    }

    func text(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    // MARK: Doc comments

    /// A doc comment's range, from its first comment's start to its last's end, and where the declaration after it
    /// starts.
    struct DocComment {
        let range: Range<Int>
        let headStart: Int
    }

    /// Every doc comment: a run of comments `convention` admits, each alone on its lines, one right below the other,
    /// followed on the next line by code. A JSDoc block is a run of its own; a line comment between it and the code,
    /// such as a lint directive, is passed over.
    func docComments(convention: DocCommentConvention) -> [DocComment] {
        var found: [DocComment] = []
        var index = 0
        while index < comments.count {
            let first = comments[index]
            guard startsLine(first.lowerBound), convention.admits(commentText(first)) else {
                index += 1
                continue
            }
            var last = first
            index += 1
            if convention == .goDoc {
                while index < comments.count, startsLine(comments[index].lowerBound),
                    newlines(between: last.upperBound, and: comments[index].lowerBound) == 1,
                    convention.admits(commentText(comments[index]))
                {
                    last = comments[index]
                    index += 1
                }
            }
            var after = last.upperBound
            var skipped = index
            // A JSDoc block may be followed by line comments before its declaration.
            while convention == .jsDoc, skipped < comments.count, startsLine(comments[skipped].lowerBound),
                newlines(between: after, and: comments[skipped].lowerBound) == 1,
                commentText(comments[skipped]).hasPrefix("//")
            {
                after = comments[skipped].upperBound
                skipped += 1
            }
            guard let next = firstNonSpace(from: after), newlines(between: after, and: next) == 1,
                let headStart = firstCodeByte(from: next), !isCommentStart(headStart)
            else { continue }
            found.append(DocComment(range: first.lowerBound ..< last.upperBound, headStart: headStart))
        }
        return found
    }

    private func commentText(_ range: Range<Int>) -> Substring {
        text(range)[...]
    }

    /// Whether only spaces and tabs lie between the start of `offset`'s line and `offset`.
    private func startsLine(_ offset: Int) -> Bool {
        var index = offset - 1
        while index >= 0, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") { index -= 1 }
        return index < 0 || bytes[index] == UInt8(ascii: "\n")
    }

    private func newlines(between start: Int, and end: Int) -> Int {
        guard start < end else { return 0 }
        return bytes[start ..< end].count { $0 == UInt8(ascii: "\n") }
    }

    /// The first byte at or after `offset` that is not whitespace; nil at the end of the text.
    private func firstNonSpace(from offset: Int) -> Int? {
        var index = offset
        while index < bytes.count, Self.isSpace(bytes[index]) { index += 1 }
        return index < bytes.count ? index : nil
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
            || byte == UInt8(ascii: "\r")
    }

    /// The first byte at or after `offset` that is neither whitespace nor a decorator line, such as `@Input()` above a
    /// class member; nil at the end of the text.
    private func firstCodeByte(from offset: Int) -> Int? {
        var index = offset
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isSpace(byte) {
                index += 1
            } else if byte == UInt8(ascii: "@"), language != .go, let end = decoratorLineEnd(from: index) {
                index = end
            } else {
                return index
            }
        }
        return nil
    }

    /// The end of a one-line decorator, `@name` or `@name(…)` with nothing after it on its line; nil otherwise.
    private func decoratorLineEnd(from start: Int) -> Int? {
        var index = start
        var depth = 0
        while index < bytes.count, bytes[index] != UInt8(ascii: "\n") {
            if !masked[index] {
                if bytes[index] == UInt8(ascii: "(") { depth += 1 }
                if bytes[index] == UInt8(ascii: ")") { depth -= 1 }
            }
            index += 1
        }
        return depth == 0 ? index : nil
    }

    private func isCommentStart(_ offset: Int) -> Bool {
        comments.contains { $0.lowerBound == offset }
    }

    // MARK: Heads

    /// A declaration head: its words and the byte where it ends.
    struct Head {
        let words: [HeadWord]
        let start: Int
        let end: Int
    }

    /// The head that starts at `start`: up to a `{` or a `;` outside brackets, or the end of its line outside
    /// brackets, and at most 400 bytes.
    func head(from start: Int) -> Head {
        var words: [HeadWord] = []
        var index = start
        var depth = 0
        let limit = min(bytes.count, start + 400)
        while index < limit {
            if masked[index] {
                while index < limit, masked[index] { index += 1 }
                words.append(.literal)
                continue
            }
            let byte = bytes[index]
            if depth == 0, byte == UInt8(ascii: "{") || byte == UInt8(ascii: ";") || byte == UInt8(ascii: "\n") {
                break
            }
            if byte == UInt8(ascii: "(") || byte == UInt8(ascii: "[") { depth += 1 }
            if byte == UInt8(ascii: ")") || byte == UInt8(ascii: "]") { depth = max(0, depth - 1) }
            if Self.isIdentifierStart(byte) {
                let wordStart = index
                while index < limit, !masked[index], Self.isIdentifier(bytes[index]) { index += 1 }
                words.append(.identifier(text(wordStart ..< index)))
                continue
            }
            if byte != UInt8(ascii: " "), byte != UInt8(ascii: "\t"), byte != UInt8(ascii: "\r") {
                words.append(.punctuation(byte))
            }
            index += 1
        }
        return Head(words: words, start: start, end: index)
    }

    /// A head's text as a signature: whitespace collapsed, and a trailing `=`, `=>` or `,` dropped.
    func signature(_ head: Head) -> String {
        var signature = text(head.start ..< head.end).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for suffix in ["=>", "=", ","] where signature.hasSuffix(suffix) {
            signature = String(signature.dropLast(suffix.count)).trimmingSuffixSpaces()
        }
        return signature
    }

    /// The body each of `offsets`, ascending, lies in: the innermost bracket that encloses it, or the top level when
    /// that bracket opens any other block, such as a function's body.
    /// - Complexity: O(bytes up to the last offset), in one pass.
    func contexts(at offsets: [Int]) -> [HeadContext] {
        var contexts: [HeadContext] = []
        var stack: [HeadContext?] = []
        var index = 0
        for offset in offsets {
            while index < offset {
                defer { index += 1 }
                guard !masked[index] else { continue }
                switch bytes[index] {
                    case UInt8(ascii: "{"): stack.append(bodyContext(openingAt: index))
                    case UInt8(ascii: "("): stack.append(groupContext(openingAt: index))
                    case UInt8(ascii: "["): stack.append(nil)
                    case UInt8(ascii: "}"), UInt8(ascii: ")"), UInt8(ascii: "]"): _ = stack.popLast()
                    default: break
                }
            }
            contexts.append((stack.last ?? nil) ?? .topLevel)
        }
        return contexts
    }

    /// What a `{` at `offset` opens, from the statement before it: a class or interface body, an enum body, or
    /// another block, nil.
    private func bodyContext(openingAt offset: Int) -> HeadContext? {
        let words = statementWords(before: offset)
        if words.contains("enum") { return .enumBody }
        if language != .go, words.contains("class") || words.contains("interface") { return .classBody }
        return nil
    }

    /// What a `(` at `offset` opens: a Go `const`, `var` or `type` group when that keyword comes right before it.
    private func groupContext(openingAt offset: Int) -> HeadContext? {
        guard language == .go else { return nil }
        var index = offset - 1
        while index >= 0, bytes[index] == UInt8(ascii: " ") || bytes[index] == UInt8(ascii: "\t") { index -= 1 }
        var start = index
        while start >= 0, Self.isIdentifier(bytes[start]) { start -= 1 }
        let word = start < index ? text(start + 1 ..< index + 1) : ""
        return ["const", "var", "type"].contains(word) ? .goGroup(word) : nil
    }

    /// The identifiers of the statement that ends at `offset`, back to the last `;`, `{` or `}` outside comments and
    /// strings, or 400 bytes.
    private func statementWords(before offset: Int) -> [String] {
        var start = offset
        while start > 0, offset - start < 400 {
            let byte = bytes[start - 1]
            if !masked[start - 1], byte == UInt8(ascii: ";") || byte == UInt8(ascii: "{") || byte == UInt8(ascii: "}") {
                break
            }
            start -= 1
        }
        var words: [String] = []
        var index = start
        while index < offset {
            guard !masked[index], Self.isIdentifierStart(bytes[index]) else {
                index += 1
                continue
            }
            let wordStart = index
            while index < offset, Self.isIdentifier(bytes[index]) { index += 1 }
            words.append(text(wordStart ..< index))
        }
        return words
    }

    static func isIdentifierStart(_ byte: UInt8) -> Bool {
        let lower = byte | 0x20
        return (lower >= UInt8(ascii: "a") && lower <= UInt8(ascii: "z")) || byte == UInt8(ascii: "_")
            || byte == UInt8(ascii: "$") || byte >= 0x80
    }

    static func isIdentifier(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
    }
}

/// Reads a declaration head's words by the language's table.
enum HeadReader {
    typealias Found = (name: String, kind: SyntaxDeclaration.Kind, signature: String)

    static func read(
        _ words: [HeadWord], language: Language, context: HeadContext, signature: String
    ) -> [Found] {
        switch language {
            case .go: go(words, context: context, signature: signature)
            default: script(words, context: context, signature: signature)
        }
    }

    // MARK: TypeScript and JavaScript

    /// Words that may lead a declaration without naming it.
    private static let modifiers: Set<String> = [
        "export", "default", "declare", "async", "abstract", "public", "private", "protected", "static", "readonly",
        "override", "accessor", "get", "set"
    ]

    private static func script(_ words: [HeadWord], context: HeadContext, signature: String) -> [Found] {
        var index = 0
        // A modifier is one only while a word follows it: `get(` names a method `get`.
        while index + 1 < words.count, case .identifier(let word) = words[index], modifiers.contains(word),
            case .identifier = words[index + 1]
        {
            index += 1
        }
        func word(_ offset: Int) -> String? {
            guard index + offset < words.count, case .identifier(let word) = words[index + offset] else { return nil }
            return word
        }
        func punctuation(_ offset: Int) -> UInt8? {
            guard index + offset < words.count, case .punctuation(let byte) = words[index + offset] else { return nil }
            return byte
        }
        func found(_ name: String?, _ kind: SyntaxDeclaration.Kind) -> [Found] {
            guard let name else { return [] }
            return [(name, kind, signature)]
        }
        switch context {
            case .enumBody:
                return found(word(0), .enumCase)
            case .classBody:
                guard let name = word(0) else { return [] }
                if name == "constructor", punctuation(1) == UInt8(ascii: "(") { return found(name, .initializer) }
                let next = punctuation(1) == UInt8(ascii: "?") ? punctuation(2) : punctuation(1)
                if next == UInt8(ascii: "(") || next == UInt8(ascii: "<") { return found(name, .function) }
                return found(name, .variable)
            case .topLevel, .goGroup:
                break
        }
        switch word(0) ?? "" {
            case "function":
                return found(punctuation(1) == UInt8(ascii: "*") ? word(2) : word(1), .function)
            case "class", "interface":
                return found(word(1).flatMap { ["extends", "implements"].contains($0) ? nil : $0 }, .type)
            case "type":
                let next = punctuation(2)
                return next == UInt8(ascii: "=") || next == UInt8(ascii: "<") ? found(word(1), .typeAlias) : []
            case "enum", "namespace", "module":
                return found(word(1), .type)
            case "const" where word(1) == "enum":
                return found(word(2), .type)
            case "const", "let", "var":
                return found(word(1), .variable)
            default:
                return []
        }
    }

    // MARK: Go

    private static func go(_ words: [HeadWord], context: HeadContext, signature: String) -> [Found] {
        if case .goGroup(let keyword) = context {
            return names(words, from: 0)
                .map { name in
                    (name, keyword == "type" ? .type : .variable, keyword + " " + signature)
                }
        }
        guard case .identifier(let keyword) = words.first else { return [] }
        switch keyword {
            case "func":
                var index = 1
                // A method's receiver: `(r *Reader)`.
                if index < words.count, words[index] == .punctuation(UInt8(ascii: "(")) {
                    var depth = 0
                    while index < words.count {
                        if words[index] == .punctuation(UInt8(ascii: "(")) { depth += 1 }
                        if words[index] == .punctuation(UInt8(ascii: ")")) { depth -= 1 }
                        index += 1
                        if depth == 0 { break }
                    }
                }
                guard index < words.count, case .identifier(let name) = words[index] else { return [] }
                return [(name, .function, signature)]
            case "type":
                guard words.count > 1, case .identifier(let name) = words[1] else { return [] }
                let isAlias = words.count > 2 && words[2] == .punctuation(UInt8(ascii: "="))
                return [(name, isAlias ? .typeAlias : .type, signature)]
            case "const", "var":
                return names(words, from: 1).map { ($0, .variable, signature) }
            default:
                return []
        }
    }

    /// The comma-separated names that start at `index`, as in `a, b = 1, 2`; none when a name is not there.
    private static func names(_ words: [HeadWord], from start: Int) -> [String] {
        var names: [String] = []
        var index = start
        while index < words.count, case .identifier(let name) = words[index] {
            names.append(name)
            guard index + 1 < words.count, words[index + 1] == .punctuation(UInt8(ascii: ",")) else { break }
            index += 2
        }
        return names
    }
}

extension String {
    fileprivate func trimmingSuffixSpaces() -> String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
