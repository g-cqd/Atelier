import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct LexerCommentTokenizationTests {
    private func makeLexTable(comments: [CommentPattern], keywords: [String: Int] = [:]) -> LexTable
    {
        var states: [LexState] = []
        if !keywords.isEmpty {
            states = buildTrieStates(keywords: keywords)
        }
        return LexTable(states: states, keywords: keywords, commentPatterns: comments)
    }

    private func buildTrieStates(keywords: [String: Int]) -> [LexState] {
        // Minimal trie for testing
        LexTableCompiler.compile(
            GrammarDefinition(
                name: "test",
                rules: keywords.map { ($0.key, Rule.string($0.key)) }
            )
        ).states
    }

    @Test
    func `Line comment is tokenized as a single extra token`() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// this is a comment")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "// this is a comment")
        #expect(commentTokens[0].isExtra)
    }

    @Test
    func `Line comment stops at newline`() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// comment\ncode")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "// comment")
    }

    @Test
    func `Doc comment is captured by prefix`() {
        let lexTable = makeLexTable(comments: [.line(prefix: "//")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/// doc comment with if keyword")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/// doc comment with if keyword")
    }

    @Test
    func `Keywords inside line comments are NOT tokenized separately`() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// if something")
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(keywordTokens.isEmpty, "Keywords inside comments should not be tokenized")
    }

    @Test
    func `Block comment is tokenized as a single extra token`() {
        let lexTable = makeLexTable(comments: [.block(open: "/*", close: "*/")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* block comment */")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/* block comment */")
        #expect(commentTokens[0].isExtra)
    }

    @Test
    func `Block comment spans multiple lines`() {
        let lexTable = makeLexTable(comments: [.block(open: "/*", close: "*/")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* line1\nline2 */")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "/* line1\nline2 */")
    }

    @Test
    func `Keywords inside block comments are NOT tokenized separately`() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.block(open: "/*", close: "*/")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("/* if else for */")
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(keywordTokens.isEmpty, "Keywords inside block comments should not be tokenized")
    }

    @Test
    func `Comment is matched before keyword when at same position`() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(
                    name: "t", rules: [("s", .choice([.string("if"), .string("//")]))])
            ).states,
            keywords: ["if": 0, "//": 1],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// if")
        #expect(tokens.first?.type == "comment")
    }

    @Test
    func `Hash comment prefix works for Python-style comments`() {
        let lexTable = makeLexTable(comments: [.line(prefix: "#")])
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("# this is a comment")
        let commentTokens = tokens.filter { $0.type == "comment" }
        #expect(commentTokens.count == 1)
        #expect(commentTokens[0].text == "# this is a comment")
    }

    @Test
    func `Code after line comment on next line is tokenized normally`() {
        let lexTable = LexTable(
            states: LexTableCompiler.compile(
                GrammarDefinition(name: "t", rules: [("s", .string("if"))])
            ).states,
            keywords: ["if": 0],
            commentPatterns: [.line(prefix: "//")]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("// comment\nif")
        let commentTokens = tokens.filter { $0.type == "comment" }
        let keywordTokens = tokens.filter { $0.type == "\"if\"" }
        #expect(commentTokens.count == 1)
        #expect(keywordTokens.count == 1, "Keyword after comment line should be tokenized")
    }
}
