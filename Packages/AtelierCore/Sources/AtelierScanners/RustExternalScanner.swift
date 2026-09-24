// Port of tree-sitter/tree-sitter-rust/src/scanner.c at
// 77a3747266f4d621d0757825e6b11edcbf991ca5 (v0.24.2).
// The MIT License (MIT). Copyright (c) 2017 Maxim Sokolov.
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

/// The external scanner for the pinned tree-sitter Rust grammar.
///
/// The value holds the number of hashes opening the current raw string.
public struct RustExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case stringContent
        case stringClose
        case rawStringLiteralStart
        case rawStringLiteralContent
        case rawStringLiteralEnd
        case floatLiteral
        case blockOuterDocMarker
        case blockInnerDocMarker
        case blockCommentContent
        case lineDocContent
        case errorSentinel
    }

    private enum BlockCommentState {
        case leftForwardSlash
        case leftAsterisk
        case continuing
    }

    private struct BlockCommentProcessing {
        var state: BlockCommentState = .continuing
        var nestingDepth = 1
    }

    /// The bundled Rust grammar's `externals`, in order.
    public static let externalNames = [
        "string_content", "string_close", "_raw_string_literal_start", "raw_string_literal_content",
        "_raw_string_literal_end", "float_literal", "_outer_block_doc_comment_marker",
        "_inner_block_doc_comment_marker", "_block_comment_content", "_line_doc_content", "_error_sentinel"
    ]

    private var openingHashCount: UInt8 = 0

    /// Creates a scanner with no open raw string delimiter.
    public init() {}

    /// Appends the one byte of raw string delimiter state.
    public func serialize(into buffer: inout [UInt8]) {
        buffer.append(openingHashCount)
    }

    /// Restores exactly one delimiter byte; any other state length resets it.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        openingHashCount = state.count == 1 ? state.first ?? 0 : 0
    }

    private static func isDigit(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.generalCategory == .decimalNumber
    }

    private static func isAlpha(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.isAlphabetic == true
    }

    private static func isSpace(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.isWhitespace == true
    }

    private static func isNumChar(_ value: UInt32) -> Bool { value == 0x5F || isDigit(value) }

    private static func processString(_ lexer: inout some ScannerLexer) -> Bool {
        var hasContent = false
        while true {
            if lexer.lookahead == 0x22 || lexer.lookahead == 0x5C { break }
            if lexer.isAtEnd { return false }
            hasContent = true
            lexer.advance(skip: false)
        }
        lexer.resultSymbol = TokenType.stringContent.rawValue
        lexer.markEnd()
        return hasContent
    }

    private mutating func scanRawStringStart(_ lexer: inout some ScannerLexer) -> Bool {
        if lexer.lookahead == 0x62 || lexer.lookahead == 0x63 { lexer.advance(skip: false) }
        if lexer.lookahead != 0x72 { return false }
        lexer.advance(skip: false)

        var openingHashCount: UInt8 = 0
        while lexer.lookahead == 0x23 {
            lexer.advance(skip: false)
            openingHashCount &+= 1
        }
        if lexer.lookahead != 0x22 { return false }
        lexer.advance(skip: false)
        self.openingHashCount = openingHashCount

        lexer.resultSymbol = TokenType.rawStringLiteralStart.rawValue
        return true
    }

    private func scanRawStringContent(_ lexer: inout some ScannerLexer) -> Bool {
        while true {
            if lexer.isAtEnd { return false }
            if lexer.lookahead == 0x22 {
                lexer.markEnd()
                lexer.advance(skip: false)
                var hashCount = 0
                while lexer.lookahead == 0x23 && hashCount < openingHashCount {
                    lexer.advance(skip: false)
                    hashCount += 1
                }
                if hashCount == openingHashCount {
                    lexer.resultSymbol = TokenType.rawStringLiteralContent.rawValue
                    return true
                }
            } else {
                lexer.advance(skip: false)
            }
        }
    }

    private func scanRawStringEnd(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.advance(skip: false)
        for _ in 0 ..< openingHashCount { lexer.advance(skip: false) }
        lexer.resultSymbol = TokenType.rawStringLiteralEnd.rawValue
        return true
    }

    private static func processFloatLiteral(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.resultSymbol = TokenType.floatLiteral.rawValue

        lexer.advance(skip: false)
        while isNumChar(lexer.lookahead) { lexer.advance(skip: false) }

        var hasFraction = false
        var hasExponent = false
        if lexer.lookahead == 0x2E {
            hasFraction = true
            lexer.advance(skip: false)
            if isAlpha(lexer.lookahead) {
                // The dot is followed by a letter: 1.max(2) => not a float but an integer
                return false
            }
            if lexer.lookahead == 0x2E { return false }
            while isNumChar(lexer.lookahead) { lexer.advance(skip: false) }
        }

        lexer.markEnd()
        if lexer.lookahead == 0x65 || lexer.lookahead == 0x45 {
            hasExponent = true
            lexer.advance(skip: false)
            if lexer.lookahead == 0x2B || lexer.lookahead == 0x2D { lexer.advance(skip: false) }
            if !isNumChar(lexer.lookahead) { return true }
            lexer.advance(skip: false)
            while isNumChar(lexer.lookahead) { lexer.advance(skip: false) }
            lexer.markEnd()
        }
        if !hasExponent && !hasFraction { return false }

        if lexer.lookahead != 0x75 && lexer.lookahead != 0x69 && lexer.lookahead != 0x66 { return true }
        lexer.advance(skip: false)
        if !isDigit(lexer.lookahead) { return true }
        while isDigit(lexer.lookahead) { lexer.advance(skip: false) }

        lexer.markEnd()
        return true
    }

    private static func processLineDocContent(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.resultSymbol = TokenType.lineDocContent.rawValue
        while true {
            if lexer.isAtEnd { return true }
            if lexer.lookahead == 0x0A {
                // Include the newline in the doc content node.
                // Line endings are useful for markdown injection.
                lexer.advance(skip: false)
                return true
            }
            lexer.advance(skip: false)
        }
    }

    private static func processLeftForwardSlash(_ processing: inout BlockCommentProcessing, current: UInt8) {
        if current == 0x2A { processing.nestingDepth += 1 }
        processing.state = .continuing
    }

    private static func processLeftAsterisk(
        _ processing: inout BlockCommentProcessing, current: UInt8, lexer: inout some ScannerLexer
    ) {
        if current == 0x2A {
            lexer.markEnd()
            processing.state = .leftAsterisk
            return
        }
        if current == 0x2F { processing.nestingDepth -= 1 }
        processing.state = .continuing
    }

    private static func processContinuing(_ processing: inout BlockCommentProcessing, current: UInt8) {
        switch current {
            case 0x2F: processing.state = .leftForwardSlash
            case 0x2A: processing.state = .leftAsterisk
            default: break
        }
    }

    private static func processBlockComment(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        var first = UInt8(truncatingIfNeeded: lexer.lookahead)
        // The first character is stored so we can safely advance inside
        // these if blocks. However, because we only store one, we can only
        // safely advance 1 time. Since there's a chance that an advance could
        // happen in one state, we must advance in all states to ensure that
        // the program ends up in a sane state prior to processing the block
        // comment if need be.
        if validSymbols[TokenType.blockInnerDocMarker.rawValue] && first == 0x21 {
            lexer.resultSymbol = TokenType.blockInnerDocMarker.rawValue
            lexer.advance(skip: false)
            return true
        }
        if validSymbols[TokenType.blockOuterDocMarker.rawValue] && first == 0x2A {
            lexer.advance(skip: false)
            lexer.markEnd()
            // If the next token is a / that means that it's an empty block comment.
            if lexer.lookahead == 0x2F { return false }
            // If the next token is a * that means that this isn't a BLOCK_OUTER_DOC_MARKER
            // as BLOCK_OUTER_DOC_MARKER's only have 2 * not 3 or more.
            if lexer.lookahead != 0x2A {
                lexer.resultSymbol = TokenType.blockOuterDocMarker.rawValue
                return true
            }
        } else {
            lexer.advance(skip: false)
        }

        if validSymbols[TokenType.blockCommentContent.rawValue] {
            var processing = BlockCommentProcessing()
            // Manually set the current state based on the first character
            switch first {
                case 0x2A:
                    processing.state = .leftAsterisk
                    if lexer.lookahead == 0x2F {
                        // This case can happen in an empty doc block comment
                        // like /*!*/. The comment has no contents, so bail.
                        return false
                    }
                case 0x2F: processing.state = .leftForwardSlash
                default: processing.state = .continuing
            }

            // For the purposes of actually parsing rust code, this
            // is incorrect as it considers an unterminated block comment
            // to be an error. However, for the purposes of syntax highlighting
            // this should be considered successful as otherwise you are not able
            // to syntax highlight a block of code prior to closing the
            // block comment
            while !lexer.isAtEnd && processing.nestingDepth != 0 {
                // Set first to the current lookahead as that is the second character
                // as we force an advance in the above code when we are checking if we
                // need to handle a block comment inner or outer doc comment signifier
                // node
                first = UInt8(truncatingIfNeeded: lexer.lookahead)
                switch processing.state {
                    case .leftForwardSlash: processLeftForwardSlash(&processing, current: first)
                    case .leftAsterisk: processLeftAsterisk(&processing, current: first, lexer: &lexer)
                    case .continuing:
                        lexer.markEnd()
                        processContinuing(&processing, current: first)
                }
                lexer.advance(skip: false)
                if first == 0x2F && processing.nestingDepth != 0 { lexer.markEnd() }
            }
            lexer.resultSymbol = TokenType.blockCommentContent.rawValue
            return true
        }
        return false
    }

    /// Scans one parser-offered external token, preserving raw delimiter state on failure.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count == Self.externalNames.count else { return false }
        // The documentation states that if the lexical analysis fails for some reason
        // they will mark every state as valid and pass it to the external scanner
        // However, we can't do anything to help them recover in that case so we
        // should just fail.
        // link: https://tree-sitter.github.io/tree-sitter/creating-parsers#external-scanners
        // If a syntax error is encountered during regular parsing, Tree-sitter's
        // first action during error recovery will be to call the external scanner's
        // scan function with all tokens marked valid. The scanner should detect this
        // case and handle it appropriately. One simple method of detection is to add
        // an unused token to the end of the externals array, for example
        // externals: $ => [$.token1, $.token2, $.error_sentinel],
        // then check whether that token is marked valid to determine whether
        // Tree-sitter is in error correction mode.
        if validSymbols[TokenType.errorSentinel.rawValue] { return false }

        if validSymbols[TokenType.blockCommentContent.rawValue]
            || validSymbols[TokenType.blockInnerDocMarker.rawValue]
            || validSymbols[TokenType.blockOuterDocMarker.rawValue]
        {
            return Self.processBlockComment(&lexer, validSymbols: validSymbols)
        }
        if validSymbols[TokenType.stringContent.rawValue] && !validSymbols[TokenType.floatLiteral.rawValue] {
            if Self.processString(&lexer) { return true }
            // process_string returns false when the next char is '"' or '\' (no
            // content to emit). Fall through so STRING_CLOSE can consume the '"'.
        }

        if validSymbols[TokenType.stringClose.rawValue] && lexer.lookahead == 0x22 {
            lexer.advance(skip: false)
            lexer.resultSymbol = TokenType.stringClose.rawValue
            lexer.markEnd()
            return true
        }
        if validSymbols[TokenType.lineDocContent.rawValue] { return Self.processLineDocContent(&lexer) }

        while Self.isSpace(lexer.lookahead) { lexer.advance(skip: true) }

        if validSymbols[TokenType.rawStringLiteralStart.rawValue]
            && (lexer.lookahead == 0x72 || lexer.lookahead == 0x62 || lexer.lookahead == 0x63)
        {
            return scanRawStringStart(&lexer)
        }
        if validSymbols[TokenType.rawStringLiteralContent.rawValue] { return scanRawStringContent(&lexer) }
        if validSymbols[TokenType.rawStringLiteralEnd.rawValue] && lexer.lookahead == 0x22 {
            return scanRawStringEnd(&lexer)
        }
        if validSymbols[TokenType.floatLiteral.rawValue] && Self.isDigit(lexer.lookahead) {
            return Self.processFloatLiteral(&lexer)
        }
        return false
    }
}
