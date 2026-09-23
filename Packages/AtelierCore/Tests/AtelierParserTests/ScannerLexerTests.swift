import Testing

@testable import AtelierParser

/// The test lexer external-scanner ports are checked with, and the scanner interface they implement.
struct ScannerLexerTests {
    /// Recognises `<<` followed by letters, tree-sitter style: it skips leading spaces, ends the token after the
    /// letters, and looks one scalar further to reject a trailing `!`.
    private struct HeredocOpenerScanner: GrammarExternalScanner {
        static let externalNames = ["heredoc_open"]
        var openedCount: UInt8 = 0

        mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
            guard validSymbols[0] else { return false }
            while lexer.lookahead == UInt32(UInt8(ascii: " ")) { lexer.advance(skip: true) }
            for _ in 0 ..< 2 {
                guard lexer.lookahead == UInt32(UInt8(ascii: "<")) else { return false }
                lexer.advance(skip: false)
            }
            var sawLetter = false
            while let scalar = Unicode.Scalar(lexer.lookahead), scalar.properties.isAlphabetic {
                lexer.advance(skip: false)
                sawLetter = true
            }
            guard sawLetter else { return false }
            lexer.markEnd()
            lexer.advance(skip: false)
            guard lexer.lookahead != UInt32(UInt8(ascii: "!")) else { return false }
            lexer.resultSymbol = 0
            openedCount += 1
            return true
        }

        func serialize(into buffer: inout [UInt8]) {
            buffer.append(openedCount)
        }

        mutating func deserialize(_ state: ArraySlice<UInt8>) {
            openedCount = state.first ?? 0
        }
    }

    @Test
    func `skipped whitespace moves the token start, and markEnd ends the token before the lookahead`() {
        var scanner = HeredocOpenerScanner()
        var lexer = StringScannerLexer("x =  <<EOF\nbody", at: 3)

        #expect(scanner.scan(&lexer, validSymbols: [true]))
        #expect(lexer.tokenStart == 5)
        #expect(lexer.tokenEnd == 10)
        #expect(lexer.resultSymbol == 0)
    }

    @Test
    func `a scanner declines a token it is not offered`() {
        var scanner = HeredocOpenerScanner()
        var lexer = StringScannerLexer("<<EOF")

        #expect(!scanner.scan(&lexer, validSymbols: [false]))
    }

    @Test
    func `state survives a serialize and deserialize round trip, and an empty state resets it`() {
        var scanner = HeredocOpenerScanner()
        var lexer = StringScannerLexer("<<A ")
        _ = scanner.scan(&lexer, validSymbols: [true])
        var buffer: [UInt8] = []
        scanner.serialize(into: &buffer)

        var restored = HeredocOpenerScanner()
        restored.deserialize(buffer[...])
        #expect(restored.openedCount == 1)
        restored.deserialize([][...])
        #expect(restored.openedCount == 0)
    }

    @Test
    func `lookahead and columns count Unicode scalars, not bytes`() {
        var lexer = StringScannerLexer("é𝄞\nab", at: 0)
        #expect(lexer.lookahead == 0xE9)
        lexer.advance(skip: false)
        #expect(lexer.lookahead == 0x1D11E)
        #expect(lexer.column() == 1)
        lexer.advance(skip: false)
        lexer.advance(skip: false)
        lexer.advance(skip: false)
        #expect(lexer.lookahead == UInt32(UInt8(ascii: "b")))
        #expect(lexer.column() == 1)
    }

    @Test
    func `the end of the input reads as zero and advancing past it does nothing`() {
        var lexer = StringScannerLexer("a", at: 1)
        #expect(lexer.isAtEnd)
        #expect(lexer.lookahead == 0)
        lexer.advance(skip: false)
        #expect(lexer.position == 1)
    }

    @Test
    func `an invalid byte reads as one replacement scalar one byte long`() {
        var lexer = StringScannerLexer(utf8: [0x61, 0xFF, 0x62], at: 1)
        #expect(lexer.lookahead == 0xFFFD)
        lexer.advance(skip: false)
        #expect(lexer.position == 2)
        #expect(lexer.lookahead == UInt32(UInt8(ascii: "b")))
    }
}
