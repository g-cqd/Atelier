public import AtelierSyntaxModel
import Foundation
import SwiftIDEUtils
import SwiftParser
import SwiftSyntax
import Synchronization

/// Swift colour from swift-syntax, the syntactic tier (PERF-11): the compiler's own parser and SwiftIDEUtils'
/// classification, as ``HighlightLayer/syntactic`` tokens.
///
/// The tokens are complete over the text: a byte without a token is plain text on purpose. An identifier that names
/// nothing swift-syntax can tell, a variable in use for one, gets no token, so a word the lexer takes for a keyword,
/// `set` in `let set = [1]`, reads as plain text once this tier lands. A declaration's name is marked
/// ``HighlightModifierSet/declaration``, with the role of what it declares.
public enum SwiftSyntaxHighlights {
    /// The largest share of a text's bytes that may lie in unexpected nodes: past it the parse reads the text as
    /// something other than Swift, and the tier fails rather than colour it.
    public static let maximumUnexpectedShare = 0.05

    /// Why a text gets no syntactic tokens.
    public enum Failure: Error, Equatable, Sendable {
        /// The work was cancelled between the parse and the classification, or during the classification.
        case cancelled
        /// More than ``maximumUnexpectedShare`` of the text's bytes lie in unexpected nodes.
        case tooManyUnexpectedBytes(share: Double)
    }

    /// The syntactic tokens of `source`, parsed and classified on ``SwiftSyntaxStack``, the calling thread waiting.
    /// - Returns: Tokens in UTF-8 byte offsets over the whole text, ascending and disjoint.
    /// - Throws: ``Failure/tooManyUnexpectedBytes(share:)`` when the text does not read as Swift.
    /// - Complexity: O(bytes of `source`), one parse.
    public static func tokens(in source: String) throws(Failure) -> [HighlightToken] {
        try SwiftSyntaxStack.run { Result { () throws(Failure) in try classify(source, isCancelled: { false }) } }.get()
    }

    /// The syntactic tokens of `source`, parsed and classified on ``SwiftSyntaxStack`` while the calling task is
    /// suspended. Cancelling the task stops the work between the parse and the classification, or within the
    /// classification.
    /// - Returns: Tokens in UTF-8 byte offsets over the whole text, ascending and disjoint.
    /// - Throws: `CancellationError` once the task is cancelled; ``Failure/tooManyUnexpectedBytes(share:)`` when the
    ///   text does not read as Swift.
    /// - Complexity: O(bytes of `source`), one parse.
    public static func tokens(in source: String) async throws -> [HighlightToken] {
        try Task.checkCancellation()
        let flag = CancellationFlag()
        let result = await withTaskCancellationHandler {
            await SwiftSyntaxStack.run {
                Result { () throws(Failure) in try classify(source, isCancelled: flag.isSet) }
            }
        } onCancel: {
            flag.set()
        }
        switch result {
            case .success(let tokens): return tokens
            case .failure(.cancelled): throw CancellationError()
            case .failure(let failure): throw failure
        }
    }

    /// Parses `source` and classifies it; runs on the caller's stack, which must be deep enough.
    static func classify(_ source: String, isCancelled: () -> Bool) throws(Failure) -> [HighlightToken] {
        let tree = Parser.parse(source: source)
        if isCancelled() { throw .cancelled }
        return try tokens(of: tree, byteCount: source.utf8.count, isCancelled: isCancelled)
    }

    /// The syntactic tokens of a parsed tree of `byteCount` bytes.
    /// - Complexity: O(nodes of `tree`): one walk for the declarations and unexpected bytes, one for the
    ///   classification.
    static func tokens(of tree: SourceFileSyntax, byteCount: Int, isCancelled: () -> Bool) throws(Failure)
        -> [HighlightToken]
    {
        let facts = TreeFacts(viewMode: .sourceAccurate)
        facts.walk(tree)
        if byteCount > 0 {
            let share = Double(facts.unexpectedBytes) / Double(byteCount)
            if share > maximumUnexpectedShare { throw .tooManyUnexpectedBytes(share: share) }
        }
        if isCancelled() { throw .cancelled }
        var tokens: [HighlightToken] = []
        tokens.reserveCapacity(byteCount / 8)
        var seen = 0
        for classified in tree.classifications {
            seen += 1
            if seen & 0x3FF == 0, isCancelled() { throw .cancelled }
            let range = classified.range.lowerBound.utf8Offset ..< classified.range.upperBound.utf8Offset
            guard !range.isEmpty else { continue }
            if classified.kind == .identifier, let role = facts.declarationNames[range.lowerBound] {
                tokens.append(HighlightToken(byteRange: range, role: role, modifiers: .declaration, layer: .syntactic))
            } else if let role = role(of: classified.kind) {
                tokens.append(HighlightToken(byteRange: range, role: role, layer: .syntactic))
            }
        }
        return tokens
    }

    /// The role a classification colours as; nil for what reads as plain text.
    static func role(of kind: SyntaxClassification) -> HighlightRole? {
        switch kind {
            case .keyword, .ifConfigDirective: .keyword
            case .attribute: .attribute
            case .lineComment, .blockComment: .comment
            case .docLineComment, .docBlockComment: .commentDocumentation
            case .stringLiteral: .string
            case .regexLiteral: .stringSpecial
            case .integerLiteral: .number
            case .floatLiteral: .numberFloat
            case .type: .type
            case .operator: .operator
            case .identifier, .dollarIdentifier, .argumentLabel, .editorPlaceholder, .none: nil
        }
    }
}

/// One walk over a tree for what the classification alone does not tell: where each declaration's name starts and
/// what it declares, and how many bytes lie in unexpected nodes.
private final class TreeFacts: SyntaxVisitor {
    /// The role of each declaration's name, by the UTF-8 offset of its first byte.
    var declarationNames: [Int: HighlightRole] = [:]
    var unexpectedBytes = 0

    override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
        unexpectedBytes += node.totalLength.utf8Length
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .type) }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .function) }
    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind { name(node.name, .function) }
    override func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind { name(node.name, .constant) }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            declarationNames[identifier.identifier.positionAfterSkippingLeadingTrivia.utf8Offset] = .variable
        }
        return .visitChildren
    }

    private func name(_ token: TokenSyntax, _ role: HighlightRole) -> SyntaxVisitorContinueKind {
        declarationNames[token.positionAfterSkippingLeadingTrivia.utf8Offset] = role
        return .visitChildren
    }
}

/// A cancellation request handed to a thread that is not a task's: set from a task's cancellation handler, read by
/// the work between its steps.
final class CancellationFlag: Sendable {
    private let value = Atomic(false)

    func set() {
        value.store(true, ordering: .releasing)
    }

    func isSet() -> Bool {
        value.load(ordering: .acquiring)
    }
}
