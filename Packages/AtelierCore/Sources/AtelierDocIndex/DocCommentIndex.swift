import SwiftParser
import SwiftSyntax

/// One source file to index, keyed by a stable URI so re-indexing can skip unchanged content.
public struct DocIndexFile: Sendable, Hashable {
    public let uri: String
    public let content: String

    public init(uri: String, content: String) {
        self.uri = uri
        self.content = content
    }
}

/// A documented declaration: its name, a body-free signature, and its doc comment rendered as markdown.
public struct DocEntry: Sendable, Equatable {
    /// The declared identifier, e.g. a function or type name, `"init"`, or `"subscript"`.
    public let name: String
    /// The declaration head with its body cut off, whitespace collapsed to single spaces.
    public let signature: String
    /// The doc comment with `///`/`/** */` markers stripped, as markdown.
    public let markdown: String
    public let uri: String
}

/// Documentation extracted from Swift doc comments, kept current by re-indexing only the files whose content
/// changed since the last `update`.
public actor DocCommentIndex {
    private struct FileState {
        let contentHash: Int
        let entries: [DocEntry]
    }

    private var files: [String: FileState] = [:]

    public init() {}

    /// Replaces the corpus. Files whose content hash is unchanged since the previous `update` are not re-parsed.
    public func update(files: [DocIndexFile]) {
        var next: [String: FileState] = [:]
        next.reserveCapacity(files.count)
        for file in files {
            let hash = Self.hash(of: file.content)
            if let existing = self.files[file.uri], existing.contentHash == hash {
                next[file.uri] = existing
            } else {
                next[file.uri] = FileState(
                    contentHash: hash, entries: Self.extractEntries(uri: file.uri, content: file.content))
            }
        }
        self.files = next
    }

    /// Entries whose name matches exactly, with `preferringURI`'s entries sorted first and a stable order otherwise.
    public func documentation(forIdentifier name: String, preferringURI uri: String?) -> [DocEntry] {
        var matches: [DocEntry] = []
        for state in files.values {
            for entry in state.entries where entry.name == name {
                matches.append(entry)
            }
        }
        matches.sort { lhs, rhs in
            if let uri {
                let lhsPreferred = lhs.uri == uri
                let rhsPreferred = rhs.uri == uri
                if lhsPreferred != rhsPreferred { return lhsPreferred }
            }
            if lhs.uri != rhs.uri { return lhs.uri < rhs.uri }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.signature < rhs.signature
        }
        return matches
    }

    private static func hash(of content: String) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        return hasher.finalize()
    }

    private static func extractEntries(uri: String, content: String) -> [DocEntry] {
        let tree = Parser.parse(source: content)
        let visitor = DocCommentVisitor(uri: uri)
        visitor.walk(tree)
        return visitor.entries
    }
}

/// Walks a syntax tree collecting an entry for every named declaration that carries a doc comment.
private final class DocCommentVisitor: SyntaxVisitor {
    private let uri: String
    private(set) var entries: [DocEntry] = []

    init(uri: String) {
        self.uri = uri
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: "init", decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: "subscript", decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let markdown = Self.markdown(from: node.leadingTrivia) else { return .visitChildren }
        let signature = Self.signature(from: DeclSyntax(node))
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            entries.append(
                DocEntry(
                    name: Self.stripBackticks(pattern.identifier.text), signature: signature, markdown: markdown,
                    uri: uri))
        }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let markdown = Self.markdown(from: node.leadingTrivia) else { return .visitChildren }
        let signature = Self.signature(from: DeclSyntax(node))
        for element in node.elements {
            entries.append(
                DocEntry(
                    name: Self.stripBackticks(element.name.text), signature: signature, markdown: markdown, uri: uri))
        }
        return .visitChildren
    }

    private func addEntry(name: String, decl: DeclSyntax, trivia: Trivia) {
        guard let markdown = Self.markdown(from: trivia) else { return }
        entries.append(
            DocEntry(
                name: Self.stripBackticks(name), signature: Self.signature(from: decl), markdown: markdown, uri: uri))
    }

    private static func stripBackticks(_ text: String) -> String {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count > 1 else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// The decl's head with its body cut off at the first top-level `{`, whitespace collapsed. A simple
    /// first-brace cut, so a closure-typed default parameter value ahead of the body would truncate early; that
    /// tradeoff is accepted for this first version.
    private static func signature(from decl: DeclSyntax) -> String {
        let text = decl.trimmedDescription
        let head = text.firstIndex(of: "{").map { text[text.startIndex ..< $0] } ?? text[...]
        return head.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The doc comment above a declaration, as markdown, or nil when there is none.
    private static func markdown(from trivia: Trivia) -> String? {
        var lines: [String] = []
        for piece in trivia.pieces {
            switch piece {
                case .docLineComment(let text):
                    lines.append(stripLineDoc(text))
                case .docBlockComment(let text):
                    lines.append(contentsOf: stripBlockDoc(text))
                default:
                    break
            }
        }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func stripLineDoc(_ text: String) -> String {
        var line = text
        if line.hasPrefix("///") { line.removeFirst(3) }
        if line.hasPrefix(" ") { line.removeFirst() }
        return line
    }

    private static func stripBlockDoc(_ text: String) -> [String] {
        var body = text
        if body.hasPrefix("/**") { body.removeFirst(3) }
        if body.hasSuffix("*/") { body.removeLast(2) }
        let rawLines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return rawLines.enumerated()
            .map { index, rawLine in
                if index == 0 {
                    return rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                }
                var line = Substring(rawLine.drop { $0 == " " || $0 == "\t" })
                if line.hasPrefix("*") {
                    line = line.dropFirst()
                    if line.hasPrefix(" ") { line = line.dropFirst() }
                }
                return String(line)
            }
    }
}
