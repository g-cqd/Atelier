// Port of tree-sitter/tree-sitter-typescript/typescript/src/scanner.c and
// common/scanner.h at f975a621f4e7f532fe322e13c4f79495e0a7b2e7 (v0.23.2).
// MIT License. Copyright (c) 2017 Max Brunsfeld.
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

/// The stateless external scanner for the pinned TypeScript grammar.
public struct TypeScriptExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case automaticSemicolon
        case templateChars
        case ternaryQmark
        case htmlComment
        case logicalOr
        case escapeSequence
        case regexPattern
        case jsxText
        case functionSignatureAutomaticSemicolon
        case errorRecovery
    }

    /// The externals of the bundled TypeScript grammar, in grammar order.
    public static let externalNames = [
        "_automatic_semicolon", "_template_chars", "_ternary_qmark", "html_comment", "||",
        "escape_sequence", "regex_pattern", "jsx_text", "_function_signature_automatic_semicolon",
        "__error_recovery"
    ]

    /// Creates a scanner with no persistent state.
    public init() {}

    /// TypeScript's C scanner serializes no state.
    public func serialize(into buffer: inout [UInt8]) {}

    /// Ignores state because TypeScript's C scanner has none, including after an empty restore.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {}

    private static func isSpace(_ scalar: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(scalar) else { return false }
        return scalar.properties.isWhitespace
    }

    private static func isAlpha(_ scalar: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(scalar) else { return false }
        return scalar.properties.isAlphabetic
    }

    private static func isDigit(_ scalar: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(scalar) else { return false }
        return scalar.properties.generalCategory == .decimalNumber
    }

    private static func scanTemplateChars(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.resultSymbol = TokenType.templateChars.rawValue
        var hasContent = false
        while true {
            lexer.markEnd()
            switch lexer.lookahead {
                case 0x60:  // `
                    return hasContent
                case 0:
                    return false
                case 0x24:  // $
                    lexer.advance(skip: false)
                    if lexer.lookahead == 0x7B { return hasContent }
                case 0x5C:  // \
                    return hasContent
                default:
                    lexer.advance(skip: false)
            }
            hasContent = true
        }
    }

    private static func scanWhitespaceAndComments(
        _ lexer: inout some ScannerLexer, scannedComment: inout Bool
    ) -> Bool {
        while true {
            while isSpace(lexer.lookahead) { lexer.advance(skip: true) }
            guard lexer.lookahead == 0x2F else {
                return true
            }
            lexer.advance(skip: true)
            if lexer.lookahead == 0x2F {
                lexer.advance(skip: true)
                while lexer.lookahead != 0 && lexer.lookahead != 0x0A {
                    lexer.advance(skip: true)
                }
                scannedComment = true
            } else if lexer.lookahead == 0x2A {  // *
                lexer.advance(skip: true)
                while lexer.lookahead != 0 {
                    if lexer.lookahead == 0x2A {
                        lexer.advance(skip: true)
                        if lexer.lookahead == 0x2F {
                            lexer.advance(skip: true)
                            break
                        }
                    } else {
                        lexer.advance(skip: true)
                    }
                }
            } else {
                return false
            }
        }
    }

    private static func scanAutomaticSemicolon(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], scannedComment: inout Bool
    ) -> Bool {
        lexer.resultSymbol = TokenType.automaticSemicolon.rawValue
        lexer.markEnd()
        while true {
            if lexer.lookahead == 0 { return true }
            if lexer.lookahead == 0x7D {
                // Automatic semicolon insertion breaks detection of object patterns
                // in a typed context:
                //   type F = ({a}: {a: number}) => number;
                // Therefore, disable automatic semicolons when followed by typing.
                repeat { lexer.advance(skip: true) } while isSpace(lexer.lookahead)
                if lexer.lookahead == 0x3A {
                    // Don't return false if we're in a ternary by checking if || is valid.
                    return validSymbols[TokenType.logicalOr.rawValue]
                }
                return true
            }
            if !isSpace(lexer.lookahead) { return false }
            if lexer.lookahead == 0x0A { break }
            lexer.advance(skip: true)
        }
        lexer.advance(skip: true)
        if !scanWhitespaceAndComments(&lexer, scannedComment: &scannedComment) {
            return false
        }
        switch lexer.lookahead {
            case 0x60, 0x2C, 0x2E, 0x3B, 0x2A, 0x25, 0x3E, 0x3C, 0x3D,
                0x3F, 0x5E, 0x7C, 0x26, 0x2F, 0x3A:
                return false
            case 0x7B:  // {
                if validSymbols[TokenType.functionSignatureAutomaticSemicolon.rawValue] { return false }
            // Don't insert a semicolon before a '[' or '(', unless we're parsing
            // a type. Detect whether we're parsing a type or an expression using
            // the validity of a binary operator token.
            case 0x28, 0x5B:  // ( [
                if validSymbols[TokenType.logicalOr.rawValue] { return false }
            // Insert a semicolon before `--` and `++`, but not before binary `+` or `-`.
            case 0x2B:  // +
                lexer.advance(skip: true)
                return lexer.lookahead == 0x2B
            case 0x2D:  // -
                lexer.advance(skip: true)
                return lexer.lookahead == 0x2D
            // Don't insert a semicolon before `!=`, but do insert one before a unary `!`.
            case 0x21:  // !
                lexer.advance(skip: true)
                return lexer.lookahead != 0x3D
            // Don't insert a semicolon before `in` or `instanceof`, but do insert one before an identifier.
            case 0x69:  // i
                lexer.advance(skip: true)
                if lexer.lookahead != 0x6E { return true }
                lexer.advance(skip: true)
                if !isAlpha(lexer.lookahead) { return false }
                for letter in "stanceof".unicodeScalars {
                    if lexer.lookahead != letter.value { return true }
                    lexer.advance(skip: true)
                }
                if !isAlpha(lexer.lookahead) { return false }
            default:
                break
        }
        return true
    }

    private static func scanTernaryQmark(_ lexer: inout some ScannerLexer) -> Bool {
        while isSpace(lexer.lookahead) { lexer.advance(skip: true) }
        if lexer.lookahead == 0x3F {
            lexer.advance(skip: false)
            // Optional chaining.
            if lexer.lookahead == 0x3F || lexer.lookahead == 0x2E { return false }
            lexer.markEnd()
            lexer.resultSymbol = TokenType.ternaryQmark.rawValue
            // TypeScript optional arguments contain the ?: sequence, possibly
            // with whitespace.
            while isSpace(lexer.lookahead) { lexer.advance(skip: false) }
            if lexer.lookahead == 0x3A || lexer.lookahead == 0x29 || lexer.lookahead == 0x2C {
                return false
            }
            if lexer.lookahead == 0x2E {
                lexer.advance(skip: false)
                return isDigit(lexer.lookahead)
            }
            return true
        }
        return false
    }

    private static func scanClosingComment(_ lexer: inout some ScannerLexer) -> Bool {
        while isSpace(lexer.lookahead) || lexer.lookahead == 0x2028 || lexer.lookahead == 0x2029 {
            lexer.advance(skip: true)
        }
        let marker: String
        if lexer.lookahead == 0x3C {
            marker = "<!--"
        } else if lexer.lookahead == 0x2D {
            marker = "-->"
        } else {
            return false
        }
        for letter in marker.unicodeScalars {
            if lexer.lookahead != letter.value { return false }
            lexer.advance(skip: false)
        }
        while lexer.lookahead != 0 && lexer.lookahead != 0x0A && lexer.lookahead != 0x2028
            && lexer.lookahead != 0x2029
        {
            lexer.advance(skip: false)
        }
        lexer.resultSymbol = TokenType.htmlComment.rawValue
        lexer.markEnd()
        return true
    }

    private static func scanJSXText(_ lexer: inout some ScannerLexer) -> Bool {
        // saw_text is true for non-whitespace or for whitespace that is not a newline and does not follow one.
        var sawText = false
        // at_newline stays true through whitespace immediately following a newline.
        var atNewline = false
        while lexer.lookahead != 0 && lexer.lookahead != 0x3C && lexer.lookahead != 0x3E
            && lexer.lookahead != 0x7B && lexer.lookahead != 0x7D && lexer.lookahead != 0x26
        {
            let isWhitespace = isSpace(lexer.lookahead)
            if lexer.lookahead == 0x0A {
                atNewline = true
            } else {
                // If at_newline is already true, and we see some whitespace, then it must stay true.
                // Otherwise, it should be false.
                //
                // |------------------------------------|
                // | at_newline | is_wspace | saw_text  |
                // |------------|-----------|-----------|
                // | false (0)  | false (0) | true  (1) |
                // | false (0)  | true  (1) | true  (1) |
                // | true  (1)  | false (0) | true  (1) |
                // | true  (1)  | true  (1) | false (0) |
                // |------------------------------------|
                atNewline = atNewline && isWhitespace
                if !atNewline { sawText = true }
            }
            lexer.advance(skip: false)
        }
        lexer.resultSymbol = TokenType.jsxText.rawValue
        return sawText
    }

    /// Scans one offered external token with the branch order of the pinned C scanner.
    /// - Returns: Whether the scanner recognized a token.
    /// - Complexity: O(n), where n is the number of scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        if validSymbols[TokenType.templateChars.rawValue] {
            if validSymbols[TokenType.automaticSemicolon.rawValue] { return false }
            return Self.scanTemplateChars(&lexer)
        }
        if validSymbols[TokenType.jsxText.rawValue] && Self.scanJSXText(&lexer) { return true }
        if validSymbols[TokenType.automaticSemicolon.rawValue]
            || validSymbols[TokenType.functionSignatureAutomaticSemicolon.rawValue]
        {
            var scannedComment = false
            let result = Self.scanAutomaticSemicolon(
                &lexer, validSymbols: validSymbols, scannedComment: &scannedComment
            )
            if !result && !scannedComment && validSymbols[TokenType.ternaryQmark.rawValue]
                && lexer.lookahead == 0x3F
            {
                return Self.scanTernaryQmark(&lexer)
            }
            return result
        }
        if validSymbols[TokenType.ternaryQmark.rawValue] { return Self.scanTernaryQmark(&lexer) }
        if validSymbols[TokenType.htmlComment.rawValue] && !validSymbols[TokenType.logicalOr.rawValue]
            && !validSymbols[TokenType.escapeSequence.rawValue] && !validSymbols[TokenType.regexPattern.rawValue]
        {
            return Self.scanClosingComment(&lexer)
        }
        return false
    }
}
