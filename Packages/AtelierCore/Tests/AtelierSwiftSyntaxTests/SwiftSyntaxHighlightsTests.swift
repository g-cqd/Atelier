import AtelierLexers
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSwiftSyntax

/// swift-syntax's colour for a Swift text, the syntactic tier (PERF-11 step 1).
struct SwiftSyntaxHighlightsTests {
    /// The tokens of `source` whose bytes spell `word`.
    private static func tokens(_ tokens: [HighlightToken], spelling word: String, in source: String)
        -> [HighlightToken]
    {
        let bytes = Array(source.utf8)
        return tokens.filter { String(decoding: bytes[$0.byteRange], as: UTF8.self) == word }
    }

    @Test
    func `a name the lexer takes for a keyword reads as a declared variable`() throws {
        let source = "let set = [1]\n"
        let lexical = LexicalHighlightEngine().highlight(utf8: Array(source.utf8), language: .swift)
        #expect(Self.tokens(lexical, spelling: "set", in: source).map(\.role) == [.keyword])

        let syntactic = try SwiftSyntaxHighlights.tokens(in: source)

        let set = Self.tokens(syntactic, spelling: "set", in: source)
        #expect(set.map(\.role) == [.variable])
        #expect(set.map(\.modifiers) == [.declaration])
        #expect(Self.tokens(syntactic, spelling: "let", in: source).map(\.role) == [.keyword])
        #expect(Self.tokens(syntactic, spelling: "1", in: source).map(\.role) == [.number])
    }

    @Test
    func `every token is syntactic, ascending and disjoint`() throws {
        let source = """
            /// A doc comment.
            struct Point: Equatable { // a comment
                var x = 1.5, label = "a \\(1) b"
                func moved(by delta: Double) -> Point { self }
            }
            """

        let tokens = try SwiftSyntaxHighlights.tokens(in: source)

        #expect(tokens.allSatisfy { $0.layer == .syntactic })
        #expect(zip(tokens, tokens.dropFirst()).allSatisfy { $0.byteRange.upperBound <= $1.byteRange.lowerBound })
        #expect(Self.tokens(tokens, spelling: "/// A doc comment.", in: source).map(\.role) == [.commentDocumentation])
        #expect(Self.tokens(tokens, spelling: "// a comment", in: source).map(\.role) == [.comment])
        #expect(Self.tokens(tokens, spelling: "Point", in: source).map(\.role) == [.type, .type])
        #expect(Self.tokens(tokens, spelling: "Equatable", in: source).map(\.role) == [.type])
        #expect(Self.tokens(tokens, spelling: "1.5", in: source).map(\.role) == [.numberFloat])
        #expect(Self.tokens(tokens, spelling: "moved", in: source).map(\.role) == [.function])
        #expect(Self.tokens(tokens, spelling: "delta", in: source).isEmpty)
        #expect(Self.tokens(tokens, spelling: "self", in: source).map(\.role) == [.keyword])
    }

    @Test
    func `a text that is not Swift fails the unexpected bytes gate`() {
        let json = #"{"name": [1, 2, {"deep": true}], "other": null, "more": "text", "list": [3, 4]}"# + "\n"

        #expect {
            try SwiftSyntaxHighlights.tokens(in: String(repeating: json, count: 20))
        } throws: { error in
            guard case .tooManyUnexpectedBytes(let share) = error as? SwiftSyntaxHighlights.Failure else {
                return false
            }
            return share > SwiftSyntaxHighlights.maximumUnexpectedShare
        }
    }

    @Test
    func `a cancelled task gets no tokens`() async {
        let source = String(repeating: "let value = compute(1, 2) + other\n", count: 2_000)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SwiftSyntaxHighlights.tokens(in: source)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func `the classification stops when asked to between two steps`() {
        #expect(throws: SwiftSyntaxHighlights.Failure.cancelled) {
            try SwiftSyntaxStack.run {
                Result { () throws(SwiftSyntaxHighlights.Failure) in
                    try SwiftSyntaxHighlights.classify("let a = 1\n", isCancelled: { true })
                }
            }
            .get()
        }
    }
}
