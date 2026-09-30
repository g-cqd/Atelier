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
    func `a type named where a type goes, or capitalized in an expression, keeps the lexer's type colour`() throws {
        let source = "let r: NSRect = NSRect(x: 0)\nlet c = NSColor.red\nvar s: Set<Swift.String> = []\nlet v = value\n"
        let syntactic = try SwiftSyntaxHighlights.tokens(in: source)

        for type in ["NSRect", "NSColor", "Set", "Swift", "String"] {
            #expect(
                Self.tokens(syntactic, spelling: type, in: source).allSatisfy { $0.role == .type }
                    && !Self.tokens(syntactic, spelling: type, in: source).isEmpty, "\(type)")
        }
        #expect(Self.tokens(syntactic, spelling: "NSRect", in: source).count == 2)
        #expect(Self.tokens(syntactic, spelling: "red", in: source).isEmpty)
        #expect(Self.tokens(syntactic, spelling: "value", in: source).isEmpty)
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
        // "Point" declares the struct the first time, at `struct Point`, and refers to it the second, as the
        // function's return type: Xcode colours the two differently (`declaration.type` vs `identifier.type`).
        #expect(Self.tokens(tokens, spelling: "Point", in: source).map(\.role) == [.typeDeclaration, .type])
        #expect(Self.tokens(tokens, spelling: "Equatable", in: source).map(\.role) == [.type])
        #expect(Self.tokens(tokens, spelling: "1.5", in: source).map(\.role) == [.numberFloat])
        // "moved" declares the function; Xcode's `declaration.other`, distinct from a call to it.
        #expect(Self.tokens(tokens, spelling: "moved", in: source).map(\.role) == [.declarationOther])
        // "delta" is a parameter's own name at its declaration, coloured the same as the function's own name.
        #expect(Self.tokens(tokens, spelling: "delta", in: source).map(\.role) == [.declarationOther])
        #expect(Self.tokens(tokens, spelling: "self", in: source).map(\.role) == [.keyword])
    }

    @Test
    func `a type's declaration, a function's declaration and their parameters colour distinctly from a use`() throws {
        let source = """
            struct Widget {
                func resize(to scale: Double) -> Widget { self }
            }
            func make(with scale: Double) -> Widget { Widget().resize(to: scale) }
            """
        let tokens = try SwiftSyntaxHighlights.tokens(in: source)

        // "Widget" declares the struct once, then names a type three more times: two return types and a call taken
        // for a type, as the lexer and Xcode take a capitalized name with no semantic tokens to say otherwise.
        // Xcode colours the declaration differently from every one of those references.
        #expect(
            Self.tokens(tokens, spelling: "Widget", in: source).map(\.role) == [.typeDeclaration, .type, .type, .type])
        // "resize" declares the method once; nothing tells a lowercase name used after `.` from a plain member
        // access without semantic tokens, so the call stays untokenized here, as it already did before this change.
        #expect(Self.tokens(tokens, spelling: "resize", in: source).map(\.role) == [.declarationOther])
        // "make" only declares a free function; nothing in this source calls it.
        #expect(Self.tokens(tokens, spelling: "make", in: source).map(\.role) == [.declarationOther])
        // "scale" is a parameter's own name at its declaration, twice; used as a plain argument at the call, it
        // colours no differently than any other unresolved name would.
        #expect(
            Self.tokens(tokens, spelling: "scale", in: source).map(\.role) == [.declarationOther, .declarationOther])
        // "with" is an argument label at its declaration; "to" is the same label, first at its declaration and then
        // at the call, each Xcode's own place for `variable.parameter`.
        #expect(Self.tokens(tokens, spelling: "with", in: source).map(\.role) == [.declarationOther])
        #expect(Self.tokens(tokens, spelling: "to", in: source).map(\.role) == [.declarationOther, .variableParameter])
    }

    @Test
    func `a regex literal colours distinctly from a string, and @concurrent as a keyword`() throws {
        let source = #"""
            @concurrent
            func matches(_ text: String) -> Bool {
                let pattern = /[a-z]+/
                return text.contains(pattern) && text == "z"
            }
            """#
        let tokens = try SwiftSyntaxHighlights.tokens(in: source)

        #expect(Self.tokens(tokens, spelling: "@concurrent", in: source).map(\.role) == [.keyword])
        #expect(Self.tokens(tokens, spelling: "/[a-z]+/", in: source).map(\.role) == [.regex])
        #expect(Self.tokens(tokens, spelling: "\"z\"", in: source).map(\.role) == [.string])
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
