// Port of tree-sitter-grammars/tree-sitter-toml/src/scanner.c at
// 64b56832c2cffe41758f28e05c756a3a98d16f41 (v0.7.0).
// MIT License. Copyright (c) Ika <ikatyang@gmail.com>.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public import AtelierParser

/// The stateless external scanner for the pinned TOML grammar.
public struct TOMLExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case lineEndingOrEOF
        case multilineBasicStringContent
        case multilineBasicStringEnd
        case multilineLiteralStringContent
        case multilineLiteralStringEnd
    }

    /// The bundled TOML grammar's `externals`, in order.
    public static let externalNames = [
        "_line_ending_or_eof", "_multiline_basic_string_content", "_multiline_basic_string_end",
        "_multiline_literal_string_content", "_multiline_literal_string_end"
    ]

    /// Creates a scanner with no persistent state.
    public init() {}

    /// TOML's C scanner serializes no state.
    public func serialize(into buffer: inout [UInt8]) {}

    /// Ignores serialized state because TOML's scanner is stateless.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {}

    private static func scanMultilineStringEnd(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], delimiter: UInt32,
        contentSymbol: TokenType, endSymbol: TokenType
    ) -> Bool {
        guard validSymbols[endSymbol.rawValue], lexer.lookahead == delimiter else { return false }

        lexer.advance(skip: false)
        lexer.markEnd()
        if lexer.lookahead != delimiter {
            guard validSymbols[contentSymbol.rawValue] else { return false }
            lexer.resultSymbol = contentSymbol.rawValue
            return true
        }

        lexer.advance(skip: false)
        if lexer.lookahead != delimiter {
            guard validSymbols[contentSymbol.rawValue] else { return false }
            lexer.markEnd()
            lexer.resultSymbol = contentSymbol.rawValue
            return true
        }

        lexer.advance(skip: false)
        if lexer.lookahead != delimiter {
            lexer.markEnd()
            lexer.resultSymbol = endSymbol.rawValue
            return true
        }
        guard validSymbols[contentSymbol.rawValue] else { return false }
        lexer.resultSymbol = contentSymbol.rawValue
        return true
    }

    /// Recognizes a value's line end or the content and end of multiline strings.
    /// - Complexity: O(n), where n is the horizontal whitespace before a line ending.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        if lexer.lookahead == 0x22 && validSymbols[TokenType.multilineBasicStringEnd.rawValue] {
            return Self.scanMultilineStringEnd(
                &lexer, validSymbols: validSymbols, delimiter: 0x22,
                contentSymbol: .multilineBasicStringContent, endSymbol: .multilineBasicStringEnd
            )
        }
        if lexer.lookahead == 0x27 && validSymbols[TokenType.multilineLiteralStringEnd.rawValue] {
            return Self.scanMultilineStringEnd(
                &lexer, validSymbols: validSymbols, delimiter: 0x27,
                contentSymbol: .multilineLiteralStringContent, endSymbol: .multilineLiteralStringEnd
            )
        }

        if validSymbols[TokenType.lineEndingOrEOF.rawValue] {
            lexer.resultSymbol = TokenType.lineEndingOrEOF.rawValue
            while lexer.lookahead == 0x20 || lexer.lookahead == 0x09 {
                lexer.advance(skip: true)
            }
            if lexer.lookahead == 0 || lexer.lookahead == 0x0A { return true }
            if lexer.lookahead == 0x0D {
                lexer.advance(skip: true)
                if lexer.lookahead == 0x0A { return true }
            }
        }
        return false
    }
}
