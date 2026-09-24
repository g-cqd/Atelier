// Port of tree-sitter-grammars/tree-sitter-lua/src/scanner.c, v0.5.0,
// commit 10fe0054734eec83049514ea2e718b2a56acd0c9.
// MIT License
// Copyright (c) 2021 Munif Tanjim
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public import AtelierParser

/// The external scanner for the pinned tree-sitter Lua grammar.
///
/// The value holds a block's closing character and delimiter level across tokens.
public struct LuaExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case blockCommentStart
        case blockCommentContent
        case blockCommentEnd
        case blockStringStart
        case blockStringContent
        case blockStringEnd
    }

    /// The bundled Lua grammar's `externals`, in order.
    public static let externalNames = [
        "_block_comment_start", "_block_comment_content", "_block_comment_end",
        "_block_string_start", "_block_string_content", "_block_string_end"
    ]

    private var endingChar: Int8 = 0
    private var levelCount: UInt8 = 0

    /// Creates a scanner in its initial state.
    public init() {}

    private mutating func resetState() {
        endingChar = 0
        levelCount = 0
    }

    /// Appends the ending character and delimiter level as two bytes.
    public func serialize(into buffer: inout [UInt8]) {
        buffer.append(UInt8(bitPattern: endingChar))
        buffer.append(levelCount)
    }

    /// Restores up to two state bytes; an empty state resets the scanner.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        guard let ending = state.first else {
            resetState()
            return
        }
        endingChar = Int8(bitPattern: ending)
        if let level = state.dropFirst().first { levelCount = level }
    }

    private static func ascii(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

    private static func consume(_ lexer: inout some ScannerLexer) { lexer.advance(skip: false) }

    private static func skip(_ lexer: inout some ScannerLexer) { lexer.advance(skip: true) }

    private static func consumeChar(_ character: Unicode.Scalar, _ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == ascii(character) else { return false }
        consume(&lexer)
        return true
    }

    private static func consumeAndCountChar(_ character: Unicode.Scalar, _ lexer: inout some ScannerLexer) -> UInt8 {
        var count: UInt8 = 0
        while lexer.lookahead == ascii(character) {
            count &+= 1
            consume(&lexer)
        }
        return count
    }

    private static func skipWhitespaces(_ lexer: inout some ScannerLexer) {
        while let scalar = Unicode.Scalar(lexer.lookahead), scalar.properties.isWhitespace {
            skip(&lexer)
        }
    }

    private mutating func scanBlockStart(_ lexer: inout some ScannerLexer) -> Bool {
        if Self.consumeChar("[", &lexer) {
            let level = Self.consumeAndCountChar("=", &lexer)

            if Self.consumeChar("[", &lexer) {
                levelCount = level
                return true
            }
        }

        return false
    }

    private func scanBlockEnd(_ lexer: inout some ScannerLexer) -> Bool {
        if Self.consumeChar("]", &lexer) {
            let level = Self.consumeAndCountChar("=", &lexer)
            if levelCount == level && Self.consumeChar("]", &lexer) {
                return true
            }
        }

        return false
    }

    private func scanBlockContent(_ lexer: inout some ScannerLexer) -> Bool {
        while lexer.lookahead != 0 {
            if lexer.lookahead == Self.ascii("]") {
                lexer.markEnd()

                if scanBlockEnd(&lexer) {
                    return true
                }
            } else {
                Self.consume(&lexer)
            }
        }

        return false
    }

    private mutating func scanCommentStart(_ lexer: inout some ScannerLexer) -> Bool {
        if Self.consumeChar("-", &lexer) && Self.consumeChar("-", &lexer) {
            lexer.markEnd()

            if scanBlockStart(&lexer) {
                lexer.markEnd()
                lexer.resultSymbol = TokenType.blockCommentStart.rawValue
                return true
            }
        }

        return false
    }

    private mutating func scanCommentContent(_ lexer: inout some ScannerLexer) -> Bool {
        if endingChar == 0 {  // block comment
            if scanBlockContent(&lexer) {
                lexer.resultSymbol = TokenType.blockCommentContent.rawValue
                return true
            }

            return false
        }

        while lexer.lookahead != 0 {
            if Int32(bitPattern: lexer.lookahead) == Int32(endingChar) {
                resetState()
                lexer.resultSymbol = TokenType.blockCommentContent.rawValue
                return true
            }

            Self.consume(&lexer)
        }

        return false
    }

    /// Scans one offered token using the same branch order as the upstream C scanner.
    /// - Returns: Whether a token was recognised.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }

        if validSymbols[TokenType.blockStringEnd.rawValue] && scanBlockEnd(&lexer) {
            resetState()
            lexer.resultSymbol = TokenType.blockStringEnd.rawValue
            return true
        }

        if validSymbols[TokenType.blockStringContent.rawValue] && scanBlockContent(&lexer) {
            lexer.resultSymbol = TokenType.blockStringContent.rawValue
            return true
        }
        if validSymbols[TokenType.blockCommentEnd.rawValue] && endingChar == 0 && scanBlockEnd(&lexer) {
            resetState()
            lexer.resultSymbol = TokenType.blockCommentEnd.rawValue
            return true
        }

        if validSymbols[TokenType.blockCommentContent.rawValue] && scanCommentContent(&lexer) {
            return true
        }

        Self.skipWhitespaces(&lexer)

        if validSymbols[TokenType.blockStringStart.rawValue] && scanBlockStart(&lexer) {
            lexer.resultSymbol = TokenType.blockStringStart.rawValue
            return true
        }
        if validSymbols[TokenType.blockCommentStart.rawValue] {
            if scanCommentStart(&lexer) {
                return true
            }
        }

        return false
    }
}
