import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct LexerTests {
    @Test
    func `Tokenize with keywords`() {
        let lexTable = LexTable(
            states: [
                LexState(transitions: [
                    // swiftlint:disable:next force_unwrapping
                    (UInt32(Character("i").asciiValue!) ... UInt32(Character("i").asciiValue!), 1)
                ]),
                LexState(transitions: [
                    // swiftlint:disable:next force_unwrapping
                    (UInt32(Character("f").asciiValue!) ... UInt32(Character("f").asciiValue!), 2)
                ]),
                LexState(accepting: 0)
            ],
            keywords: ["if": 0]
        )
        let lexer = Lexer(lexTable: lexTable)
        let tokens = lexer.tokenize("if")
        #expect(tokens.contains(where: { $0.text == "if" }))
    }

    @Test
    func `Tokenize skips whitespace`() {
        let lexer = Lexer(lexTable: LexTable())
        let tokens = lexer.tokenize("a b")
        #expect(tokens.count == 3)  // 'a', whitespace, 'b'
        #expect(tokens[1].isExtra)
    }
}
