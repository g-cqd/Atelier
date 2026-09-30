public import AtelierSyntaxModel
import SwiftParser
import SwiftSyntax

/// One parse of a Swift text and everything the app learns from it (PERF-11 step 3): the colour tier's tokens, the
/// intraline diff's token boundaries, and the declarations hover documents.
public enum SwiftSyntaxFacts {
    /// Parses `text` once on ``SwiftSyntaxStack``, the calling thread waiting, and extracts its facts; nil when
    /// `isCancelled` answers true between two steps.
    /// - Complexity: One parse, then O(nodes) for each of the walks.
    public static func extract(_ text: String, isCancelled: @escaping @Sendable () -> Bool = { false }) -> SyntaxFacts?
    {
        SwiftSyntaxStack.run { extractInPlace(text, isCancelled: isCancelled) }
    }

    /// The facts `store` keeps for `revision`, or those one parse of `text` finds, which `store` keeps; the calling
    /// thread waits while ``SwiftSyntaxStack`` parses. Call it from synchronous code only; a task awaits the
    /// asynchronous variant.
    public static func facts(for revision: SourceRevision, text: String, in store: SyntaxFactsStore) -> SyntaxFacts? {
        if let kept = store.facts(for: revision) { return kept }
        return SwiftSyntaxStack.run { store.facts(for: revision) { extractInPlace(text, isCancelled: { false }) } }
    }

    /// The facts `store` keeps for `revision`, or those one parse of `text` finds on ``SwiftSyntaxStack`` while the
    /// calling task is suspended, which `store` keeps; nil when `isCancelled` answers true between two steps.
    public static func facts(
        for revision: SourceRevision, text: String, in store: SyntaxFactsStore,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> SyntaxFacts? {
        if let kept = store.facts(for: revision) { return kept }
        return await SwiftSyntaxStack.run {
            store.facts(for: revision) { extractInPlace(text, isCancelled: isCancelled) }
        }
    }

    /// The declarations of `text` alone, from one parse and one walk on ``SwiftSyntaxStack``, the calling thread
    /// waiting: what hover indexes of a file it keeps no other fact of.
    public static func declarations(in text: String) -> [SyntaxDeclaration] {
        SwiftSyntaxStack.run {
            let walk = TreeWalk(collectsDeclarations: true)
            walk.walk(Parser.parse(source: text))
            return walk.declarations
        }
    }

    /// ``extract(_:isCancelled:)`` on the caller's stack, which must be deep enough.
    static func extractInPlace(_ text: String, isCancelled: () -> Bool) -> SyntaxFacts? {
        let tree = Parser.parse(source: text)
        if isCancelled() { return nil }
        let walk = TreeWalk(collectsDeclarations: true, collectsScopes: true)
        walk.walk(tree)
        let byteCount = text.utf8.count
        let share = byteCount > 0 ? Double(walk.unexpectedBytes) / Double(byteCount) : 0
        var highlights: [HighlightToken]?
        if share <= SwiftSyntaxHighlights.maximumUnexpectedShare {
            let parsed = SwiftSyntaxHighlights.Parsed(
                tree: tree, declarationNames: walk.declarationNames, typeReferences: walk.typeReferences)
            do {
                highlights = try parsed.tokens(in: nil, isCancelled: isCancelled)
            } catch {
                return nil
            }
        }
        if isCancelled() { return nil }
        return SyntaxFacts(
            tokenBoundaries: SwiftSyntaxTokenRanges.tokenBoundaries(of: tree, text: text),
            declarations: walk.declarations, highlights: highlights, unexpectedShare: share, scopes: walk.scopes)
    }
}

/// One walk over a tree for what the classification alone does not tell: where each declaration's name starts and
/// what it declares, how many bytes lie in unexpected nodes, and, when asked, every declaration with its doc comment
/// and every brace pair that opens a scope (DIFF-03).
final class TreeWalk: SyntaxVisitor {
    /// The colour role of each declaration's name, by the UTF-8 offset of its first byte.
    private(set) var declarationNames: [Int: HighlightRole] = [:]
    /// The UTF-8 offset of each name that refers to a type: where a type goes, or capitalized in an expression.
    private(set) var typeReferences: Set<Int> = []
    private(set) var unexpectedBytes = 0
    private(set) var declarations: [SyntaxDeclaration] = []
    /// The scopes, by their opening brace: the walk visits an enclosing node before the nodes it holds.
    private(set) var scopes: [SyntaxScope] = []
    private let collectsDeclarations: Bool
    private let collectsScopes: Bool

    init(collectsDeclarations: Bool, collectsScopes: Bool = false) {
        self.collectsDeclarations = collectsDeclarations
        self.collectsScopes = collectsScopes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
        scope(node.leftBrace, node.rightBrace, kind: .type)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        let isBody =
            node.parent.map {
                $0.is(FunctionDeclSyntax.self) || $0.is(InitializerDeclSyntax.self)
                    || $0.is(DeinitializerDeclSyntax.self) || $0.is(AccessorDeclSyntax.self)
            } ?? false
        return scope(node.leftBrace, node.rightBrace, kind: isBody ? .function : .controlFlow)
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        scope(node.leftBrace, node.rightBrace, kind: .function)
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        scope(node.leftBrace, node.rightBrace, kind: .closure)
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        scope(node.leftBrace, node.rightBrace, kind: .controlFlow)
    }

    /// Records the scope `left` and `right` enclose, when both braces are written.
    private func scope(_ left: TokenSyntax, _ right: TokenSyntax, kind: SyntaxScope.Kind) -> SyntaxVisitorContinueKind {
        guard collectsScopes, left.presence == .present, right.presence == .present else { return .visitChildren }
        let start = left.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = right.endPositionBeforeTrailingTrivia.utf8Offset
        if end > start { scopes.append(SyntaxScope(range: start ..< end, kind: kind)) }
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        typeReferences.insert(node.name.positionAfterSkippingLeadingTrivia.utf8Offset)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        typeReferences.insert(node.name.positionAfterSkippingLeadingTrivia.utf8Offset)
        return .visitChildren
    }

    /// A capitalized name in an expression, `NSRect(…)` or `NSColor.red`, is taken for a type, as the lexer and Xcode
    /// take it: without the compiler's semantics nothing tells a type from a capitalized value, which Swift rarely has.
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if case .identifier = node.baseName.tokenKind, node.baseName.text.first?.isUppercase == true {
            typeReferences.insert(node.baseName.positionAfterSkippingLeadingTrivia.utf8Offset)
        }
        return .visitChildren
    }

    override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
        unexpectedBytes += node.totalLength.utf8Length
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .type)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .type)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .type)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .type)
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .type)
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .type, kind: .typeAlias)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .function, kind: .function)
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(node, name: node.name, role: .function, kind: .macro)
    }

    /// Coloured as a type's name; hover has never listed an associated type, and still does not.
    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        declarationNames[node.name.positionAfterSkippingLeadingTrivia.utf8Offset] = .type
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if collectsDeclarations { record(DeclSyntax(node), name: "init", kind: .initializer) }
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        if collectsDeclarations { record(DeclSyntax(node), name: "subscript", kind: .subscript) }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements {
            declarationNames[element.name.positionAfterSkippingLeadingTrivia.utf8Offset] = .constant
        }
        guard collectsDeclarations else { return .visitChildren }
        let documentation = Self.documentation(from: node.leadingTrivia)
        let signature = documentation.map { _ in Self.signature(of: DeclSyntax(node)) }
        for element in node.elements {
            declarations.append(
                SyntaxDeclaration(
                    name: Self.strippingBackticks(element.name.text), kind: .enumCase, range: Self.range(of: node),
                    documentation: documentation, signature: signature))
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier }
        for name in names { declarationNames[name.positionAfterSkippingLeadingTrivia.utf8Offset] = .variable }
        guard collectsDeclarations else { return .visitChildren }
        let documentation = Self.documentation(from: node.leadingTrivia)
        let signature = documentation.map { _ in Self.signature(of: DeclSyntax(node)) }
        for name in names {
            declarations.append(
                SyntaxDeclaration(
                    name: Self.strippingBackticks(name.text), kind: .variable, range: Self.range(of: node),
                    documentation: documentation, signature: signature))
        }
        return .visitChildren
    }

    private func declare(
        _ node: some DeclSyntaxProtocol, name: TokenSyntax, role: HighlightRole, kind: SyntaxDeclaration.Kind
    ) -> SyntaxVisitorContinueKind {
        declarationNames[name.positionAfterSkippingLeadingTrivia.utf8Offset] = role
        if collectsDeclarations { record(DeclSyntax(node), name: name.text, kind: kind) }
        return .visitChildren
    }

    private func record(_ decl: DeclSyntax, name: String, kind: SyntaxDeclaration.Kind) {
        let documentation = Self.documentation(from: decl.leadingTrivia)
        declarations.append(
            SyntaxDeclaration(
                name: Self.strippingBackticks(name), kind: kind, range: Self.range(of: decl),
                documentation: documentation, signature: documentation.map { _ in Self.signature(of: decl) }))
    }

    private static func range(of node: some SyntaxProtocol) -> Range<Int> {
        node.positionAfterSkippingLeadingTrivia.utf8Offset ..< node.endPositionBeforeTrailingTrivia.utf8Offset
    }

    private static func strippingBackticks(_ text: String) -> String {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count > 1 else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// The declaration up to its first `{`, whitespace collapsed; a closure default value ahead of the body cuts it
    /// short.
    private static func signature(of decl: DeclSyntax) -> String {
        let text = decl.trimmedDescription
        let head = text.firstIndex(of: "{").map { text[text.startIndex ..< $0] } ?? text[...]
        return head.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The doc comment above a declaration, as markdown, or nil when there is none.
    private static func documentation(from trivia: Trivia) -> String? {
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
