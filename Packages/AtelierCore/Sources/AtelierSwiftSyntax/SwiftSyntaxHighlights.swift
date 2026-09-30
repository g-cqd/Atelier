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
/// ``HighlightModifierSet/declaration``, with the role of what it declares. A type named where a type goes, or a
/// capitalized name used as one in an expression, `NSRect(…)` or `NSColor.red`, is a type, as the lexer and Xcode
/// colour it: classification alone left them plain, wiping the colour the lexer had given them.
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
        try Parsed(source, isCancelled: isCancelled).tokens(in: nil, isCancelled: isCancelled)
    }

    /// A text parsed once, with what one walk over its tree found, classified a range at a time: the tier colours the
    /// visible lines first, then the rest, from one parse.
    struct Parsed: Sendable {
        let tree: SourceFileSyntax
        /// The role of each declaration's name, by the UTF-8 offset of its first byte.
        let declarationNames: [Int: HighlightRole]
        /// The UTF-8 offset of the first byte of each name that refers to a type.
        let typeReferences: Set<Int>

        /// Parses `source` and walks its tree once, on the caller's stack, which must be deep enough.
        /// - Throws: ``Failure/cancelled`` when asked to stop after the parse; ``Failure/tooManyUnexpectedBytes(share:)``
        ///   past the gate.
        init(_ source: String, isCancelled: () -> Bool) throws(Failure) {
            let tree = Parser.parse(source: source)
            if isCancelled() { throw .cancelled }
            let walk = TreeWalk(collectsDeclarations: false)
            walk.walk(tree)
            let byteCount = source.utf8.count
            if byteCount > 0 {
                let share = Double(walk.unexpectedBytes) / Double(byteCount)
                if share > SwiftSyntaxHighlights.maximumUnexpectedShare { throw .tooManyUnexpectedBytes(share: share) }
            }
            self.init(tree: tree, declarationNames: walk.declarationNames, typeReferences: walk.typeReferences)
        }

        /// A tree parsed and walked already, as the facts' extraction has it.
        init(tree: SourceFileSyntax, declarationNames: [Int: HighlightRole], typeReferences: Set<Int>) {
            self.tree = tree
            self.declarationNames = declarationNames
            self.typeReferences = typeReferences
        }

        /// The syntactic tokens that meet `bytes`, a UTF-8 range of the text, or every token for nil; a token that
        /// crosses the range's edge comes whole. Runs on the caller's stack, which must be deep enough.
        /// - Complexity: O(nodes that meet `bytes`)
        func tokens(in bytes: Range<Int>?, isCancelled: () -> Bool) throws(Failure) -> [HighlightToken] {
            if isCancelled() { throw .cancelled }
            let classifications =
                bytes.map {
                    tree.classifications(
                        in: AbsolutePosition(utf8Offset: $0.lowerBound) ..< AbsolutePosition(utf8Offset: $0.upperBound))
                } ?? tree.classifications
            var tokens: [HighlightToken] = []
            tokens.reserveCapacity((bytes?.count ?? tree.totalLength.utf8Length) / 8)
            var seen = 0
            for classified in classifications {
                seen += 1
                if seen & 0x3FF == 0, isCancelled() { throw .cancelled }
                let range = classified.range.lowerBound.utf8Offset ..< classified.range.upperBound.utf8Offset
                guard !range.isEmpty else { continue }
                if classified.kind == .identifier, let role = declarationNames[range.lowerBound] {
                    tokens.append(
                        HighlightToken(byteRange: range, role: role, modifiers: .declaration, layer: .syntactic))
                } else if classified.kind == .identifier, typeReferences.contains(range.lowerBound) {
                    tokens.append(HighlightToken(byteRange: range, role: .type, layer: .syntactic))
                } else if let role = SwiftSyntaxHighlights.role(of: classified.kind) {
                    tokens.append(HighlightToken(byteRange: range, role: role, layer: .syntactic))
                }
            }
            return tokens
        }
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
