import Foundation
import Testing

@testable import AtelierGrammar

/// How the lexer's automaton chooses between tokens, by tree-sitter's rules.
@Suite
struct LexAutomatonTests {
    private static let keyword = LexicalToken(name: "\"if\"", rule: .string("if"), implicitPrecedence: 2)
    private static let identifier = LexicalToken(name: "identifier", rule: .pattern("[a-z]+"), isNamed: true)

    @Test
    func `The longest match wins`() throws {
        let table = try Self.table([Self.keyword, Self.identifier])

        #expect(Self.firstToken(of: "iffy", in: table) == Lexed(token: 1, range: 0 ..< 4))
    }

    @Test
    func `A string beats a pattern that reads the same text`() throws {
        let table = try Self.table([Self.identifier, Self.keyword])

        #expect(Self.firstToken(of: "if", in: table) == Lexed(token: 1, range: 0 ..< 2))
    }

    @Test
    func `A mode reads only the tokens valid in it`() throws {
        let table = try Self.table([Self.keyword, Self.identifier], valid: [0])

        #expect(Self.firstToken(of: "iffy", in: table) == Lexed(token: 0, range: 0 ..< 2))
    }

    @Test
    func `Separators before a token are read but left out of it`() throws {
        let table = try Self.table([Self.keyword], separators: [.pattern(#"\s"#)])

        #expect(Self.firstToken(of: " \n if", in: table) == Lexed(token: 0, range: 3 ..< 5))
    }

    @Test
    func `An immediate token takes no separator before it`() throws {
        var immediate = Self.keyword
        immediate.isImmediate = true
        let table = try Self.table([immediate], separators: [.pattern(#"\s"#)])

        #expect(Self.firstToken(of: " if", in: table) == nil)
    }

    /// JSON's string tokens: a comment would read to the end of the line and a quote after a space would skip the
    /// space, but string content, of precedence 1, has already ended with a higher precedence.
    @Test(arguments: [(#"//x""#, 0 ..< 3), (#" ""#, 0 ..< 1)])
    func `A token of higher precedence stops a longer match of a lower one`(text: String, range: Range<Int>) throws {
        let quote = LexicalToken(name: "\"\\\"\"", rule: .string("\""), implicitPrecedence: 2)
        let content = LexicalToken(
            name: "string_content", rule: .prec(1, .pattern(#"[^\\"\n]+"#)), isImmediate: true, isNamed: true,
            completionPrecedence: 1, implicitPrecedence: 1)
        let comment = LexicalToken(name: "comment", rule: .pattern("//.*"), isNamed: true, isExtra: true)
        let table = try Self.table([quote, content, comment], separators: [.pattern(#"\s"#)])

        #expect(Self.firstToken(of: text, in: table) == Lexed(token: 1, range: range))
    }

    @Test
    func `A token that matches the empty string fails the compile`() throws {
        // `word` would end before reading anything, and a mode it is valid in could then read no other token.
        let json = """
            {
                "name": "empty",
                "rules": {
                    "source": {
                        "type": "SEQ",
                        "members": [{"type": "STRING", "value": "a"}, {"type": "SYMBOL", "name": "word"}]
                    },
                    "word": {"type": "PATTERN", "value": "[a-z]*"}
                }
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))

        #expect(throws: GrammarError.invalidRuleType("Token `word` matches the empty string")) {
            try ParseTableCompiler.compile(grammar)
        }
    }

    private struct Lexed: Equatable {
        var token: Int
        /// In scalars.
        var range: Range<Int>
    }

    /// A table whose one parse state has `valid` tokens, all of `tokens` by default.
    private static func table(
        _ tokens: [LexicalToken],
        separators: [Rule] = [],
        valid: [Int]? = nil
    ) throws -> LexTable {
        try LexTableCompiler.compile(
            tokens: tokens, separators: separators, validTokens: [valid ?? Array(tokens.indices)])
    }

    /// The token the automaton reads first from `text` in the mode of parse state 0: the last it accepted before it
    /// could read no further, leaving out what it skipped.
    private static func firstToken(of text: String, in table: LexTable) -> Lexed? {
        let scalars = Array(text.unicodeScalars)
        var state = table.modeStarts[table.stateModes[0]]
        var tokenStart = 0
        var lexed: Lexed?
        for (index, scalar) in scalars.enumerated() {
            guard
                let transition = table.automaton[state].transitions
                    .first(where: { $0.lower <= scalar.value && scalar.value <= $0.upper })
            else { break }
            if transition.skips { tokenStart = index + 1 }
            state = transition.target
            if let token = table.automaton[state].accept, index + 1 > tokenStart {
                lexed = Lexed(token: token, range: tokenStart ..< index + 1)
            }
        }
        return lexed
    }
}
