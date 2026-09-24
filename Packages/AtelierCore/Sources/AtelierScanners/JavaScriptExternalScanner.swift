// Port of tree-sitter/tree-sitter-javascript/src/scanner.c at
// 44c892e0be055ac465d5eeddae6d3e194424e7de (v0.25.0).
// MIT License. Copyright (c) 2014 Max Brunsfeld.
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

/// The stateless external scanner for the pinned JavaScript grammar.
public struct JavaScriptExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case automaticSemicolon
        case templateChars
        case ternaryQmark
        case htmlComment
        case logicalOr
        case escapeSequence
        case regexPattern
        case jsxText
    }

    private enum WhitespaceResult {
        case reject  // Semicolon is illegal, ie a syntax error occurred
        case noNewline  // Unclear if semicolon will be legal, continue
        case accept  // Semicolon is legal, assuming a comment was encountered
    }

    /// The externals of the bundled JavaScript grammar, in grammar order.
    public static let externalNames = [
        "_automatic_semicolon", "_template_chars", "_ternary_qmark", "html_comment", "||",
        "escape_sequence", "regex_pattern", "jsx_text"
    ]

    /// Creates a scanner with no persistent state.
    public init() {}

    /// JavaScript's C scanner serializes no state.
    public func serialize(into buffer: inout [UInt8]) {}

    /// Ignores state because JavaScript's C scanner has none, including after an empty restore.
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

    /// When `consume` is false, consume only enough to check if a comment permits a semicolon.
    private static func scanWhitespaceAndComments(
        _ lexer: inout some ScannerLexer, scannedComment: inout Bool, consume: Bool
    ) -> WhitespaceResult {
        var sawBlockNewline = false
        while true {
            while isSpace(lexer.lookahead) { lexer.advance(skip: true) }
            guard lexer.lookahead == 0x2F else {
                return .accept
            }
            lexer.advance(skip: true)
            if lexer.lookahead == 0x2F {
                lexer.advance(skip: true)
                while lexer.lookahead != 0 && lexer.lookahead != 0x0A && lexer.lookahead != 0x2028
                    && lexer.lookahead != 0x2029
                {
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
                            scannedComment = true
                            if lexer.lookahead != 0x2F && !consume {
                                return sawBlockNewline ? .accept : .noNewline
                            }
                            break
                        }
                    } else if lexer.lookahead == 0x0A || lexer.lookahead == 0x2028
                        || lexer.lookahead == 0x2029
                    {
                        sawBlockNewline = true
                        lexer.advance(skip: true)
                    } else {
                        lexer.advance(skip: true)
                    }
                }
            } else {
                return .reject
            }
        }
    }

    private static func scanAutomaticSemicolon(
        _ lexer: inout some ScannerLexer, commentCondition: Bool, scannedComment: inout Bool
    ) -> Bool {
        lexer.resultSymbol = TokenType.automaticSemicolon.rawValue
        lexer.markEnd()
        while true {
            if lexer.lookahead == 0 { return true }
            if lexer.lookahead == 0x2F {
                let result = scanWhitespaceAndComments(&lexer, scannedComment: &scannedComment, consume: false)
                if result == .reject { return false }
                if result == .accept && commentCondition && lexer.lookahead != 0x2C && lexer.lookahead != 0x3D {
                    return true
                }
            }
            if lexer.lookahead == 0x7D { return true }
            if lexer.isAtIncludedRangeStart { return true }
            if lexer.lookahead == 0x0A || lexer.lookahead == 0x2028 || lexer.lookahead == 0x2029 { break }
            if !isSpace(lexer.lookahead) { return false }
            lexer.advance(skip: true)
        }
        lexer.advance(skip: true)
        if scanWhitespaceAndComments(&lexer, scannedComment: &scannedComment, consume: true) == .reject {
            return false
        }
        switch lexer.lookahead {
            case 0x60, 0x2C, 0x3A, 0x3B, 0x2A, 0x25, 0x3E, 0x3C, 0x3D,
                0x5B, 0x28, 0x3F, 0x5E, 0x7C, 0x26, 0x2F:
                return false
            // Insert a semicolon before decimals literals but not otherwise.
            case 0x2E:  // .
                lexer.advance(skip: true)
                return isDigit(lexer.lookahead)
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
            if lexer.lookahead == 0x3F { return false }
            lexer.markEnd()
            lexer.resultSymbol = TokenType.ternaryQmark.rawValue
            if lexer.lookahead == 0x2E {
                lexer.advance(skip: false)
                return isDigit(lexer.lookahead)
            }
            return true
        }
        return false
    }

    private static func scanHTMLComment(_ lexer: inout some ScannerLexer) -> Bool {
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
        if validSymbols[TokenType.automaticSemicolon.rawValue] {
            var scannedComment = false
            let result = Self.scanAutomaticSemicolon(
                &lexer, commentCondition: !validSymbols[TokenType.logicalOr.rawValue],
                scannedComment: &scannedComment
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
            return Self.scanHTMLComment(&lexer)
        }
        return false
    }
}
