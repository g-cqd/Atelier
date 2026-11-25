// Port of tree-sitter/tree-sitter-css/src/scanner.c at
// dda5cfc5722c429eaba1c910ca32c2c0c5bb1a3f (v0.25.0).
// MIT License. Copyright (c) 2018 Max Brunsfeld.
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

/// The stateless external scanner for the pinned CSS grammar.
public struct CSSExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case descendantOp
        case pseudoClassSelectorColon
        case errorRecovery
    }

    /// The bundled CSS grammar's `externals`, in order.
    public static let externalNames = [
        "_descendant_operator", "_pseudo_class_selector_colon", "__error_recovery"
    ]

    /// Creates a scanner with no persistent state.
    public init() {}

    /// CSS's C scanner serializes no state.
    public func serialize(into buffer: inout [UInt8]) {}

    /// Ignores serialized state because CSS's scanner is stateless.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {}

    private static func isSpace(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isWhitespace
    }

    private static func isAlnum(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.generalCategory == .decimalNumber
    }

    private static func scanDescendant(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.resultSymbol = TokenType.descendantOp.rawValue
        lexer.advance(skip: true)
        while isSpace(lexer.lookahead) { lexer.advance(skip: true) }
        lexer.markEnd()

        if [0x23, 0x2E, 0x5B, 0x2D, 0x2A].contains(lexer.lookahead) || isAlnum(lexer.lookahead) {
            return true
        }
        if lexer.lookahead == 0x3A {
            lexer.advance(skip: false)
            if isSpace(lexer.lookahead) { return false }
            while true {
                if lexer.lookahead == 0x3B || lexer.lookahead == 0x7D || lexer.isAtEnd { return false }
                if lexer.lookahead == 0x7B { return true }
                lexer.advance(skip: false)
            }
        }
        return false
    }

    private static func scanPseudoClassColon(_ lexer: inout some ScannerLexer) -> Bool {
        while isSpace(lexer.lookahead) { lexer.advance(skip: true) }
        guard lexer.lookahead == 0x3A else { return false }
        lexer.advance(skip: false)
        if lexer.lookahead == 0x3A { return false }
        lexer.markEnd()
        lexer.resultSymbol = TokenType.pseudoClassSelectorColon.rawValue

        // We need a `{` to be a pseudo class selector, a `;` indicates a property.
        // This does not apply if we're in a comment, however.
        var inComment = false
        while lexer.lookahead != 0x3B && lexer.lookahead != 0x7D && !lexer.isAtEnd {
            lexer.advance(skip: false)
            if lexer.lookahead == 0x7B && !inComment { return true }
            if lexer.lookahead == 0x2F && !inComment {
                lexer.advance(skip: false)
                if lexer.lookahead == 0x2A { inComment = true }
            } else if lexer.lookahead == 0x2A && inComment {
                lexer.advance(skip: false)
                if lexer.lookahead == 0x2F { inComment = false }
            }
        }

        // At EOF, prefer an erroneous pseudo-class selector over an erroneous property.
        return lexer.isAtEnd
    }

    /// Recognizes whitespace between selectors or a pseudo-class colon.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count,
            !validSymbols[TokenType.errorRecovery.rawValue]
        else { return false }

        if Self.isSpace(lexer.lookahead) && validSymbols[TokenType.descendantOp.rawValue]
            && Self.scanDescendant(&lexer)
        {
            return true
        }

        if validSymbols[TokenType.pseudoClassSelectorColon.rawValue] {
            return Self.scanPseudoClassColon(&lexer)
        }
        return false
    }
}
