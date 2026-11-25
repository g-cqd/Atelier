// Port of tree-sitter-grammars/tree-sitter-markdown/tree-sitter-markdown/src/scanner.c,
// commit f969cd3ae3f9fbd4e43205431d0ae286014c05b5 (v0.5.3).
// MIT License. Copyright (c) 2021 Matthias Deiml.
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

/// The block grammar's external scanner for the pinned Markdown grammar.
public struct MarkdownExternalScanner: GrammarExternalScanner {
    enum Token: Int {
        case lineEnding, softLineEnding, blockClose, blockContinuation, blockQuoteStart
        case indentedChunkStart, atxH1Marker, atxH2Marker, atxH3Marker, atxH4Marker, atxH5Marker, atxH6Marker
        case setextH1Underline, setextH2Underline, thematicBreak
        case listMarkerMinus, listMarkerPlus, listMarkerStar, listMarkerParenthesis, listMarkerDot
        case listMarkerMinusDontInterrupt, listMarkerPlusDontInterrupt, listMarkerStarDontInterrupt
        case listMarkerParenthesisDontInterrupt, listMarkerDotDontInterrupt
        case fencedCodeBlockStartBacktick, fencedCodeBlockStartTilde, blankLineStart
        case fencedCodeBlockEndBacktick, fencedCodeBlockEndTilde
        case htmlBlock1Start, htmlBlock1End, htmlBlock2Start, htmlBlock3Start, htmlBlock4Start
        case htmlBlock5Start, htmlBlock6Start, htmlBlock7Start
        case closeBlock, noIndentedChunk, error, triggerError, eof, minusMetadata, plusMetadata
        case pipeTableStart, pipeTableLineEnding
    }

    // LIST_ITEM is a list item with minimal indentation (content begins at indent
    // level 2) while LIST_ITEM_MAX_INDENTATION represents maximal indentation.
    // ANONYMOUS represents a block whose close is not handled by the scanner.
    enum Block: Int {
        case blockQuote, indentedCodeBlock, listItem, listItem1Indentation, listItem2Indentation
        case listItem3Indentation, listItem4Indentation, listItem5Indentation, listItem6Indentation
        case listItem7Indentation, listItem8Indentation, listItem9Indentation, listItem10Indentation
        case listItem11Indentation, listItem12Indentation, listItem13Indentation, listItem14Indentation
        case listItemMaxIndentation, fencedCodeBlock, anonymous
    }

    /// The 47 externals in the pinned grammar's order.
    public static let externalNames = [
        "_line_ending", "_soft_line_ending", "_block_close", "block_continuation", "_block_quote_start",
        "_indented_chunk_start", "atx_h1_marker", "atx_h2_marker", "atx_h3_marker", "atx_h4_marker",
        "atx_h5_marker", "atx_h6_marker", "setext_h1_underline", "setext_h2_underline", "_thematic_break",
        "_list_marker_minus", "_list_marker_plus", "_list_marker_star", "_list_marker_parenthesis", "_list_marker_dot",
        "_list_marker_minus_dont_interrupt", "_list_marker_plus_dont_interrupt", "_list_marker_star_dont_interrupt",
        "_list_marker_parenthesis_dont_interrupt", "_list_marker_dot_dont_interrupt",
        "_fenced_code_block_start_backtick", "_fenced_code_block_start_tilde", "_blank_line_start",
        "_fenced_code_block_end_backtick", "_fenced_code_block_end_tilde", "_html_block_1_start", "_html_block_1_end",
        "_html_block_2_start", "_html_block_3_start", "_html_block_4_start", "_html_block_5_start",
        "_html_block_6_start", "_html_block_7_start", "_close_block", "_no_indented_chunk", "_error",
        "_trigger_error", "_eof", "minus_metadata", "plus_metadata", "_pipe_table_start",
        "_pipe_table_line_ending"
    ]

    static let stateMatching = 1 << 0
    static let stateWasSoftLineBreak = 1 << 1
    static let stateCloseBlock = 1 << 4
    static let maximumBlocks = 254  // (1024 serialization bytes - 5 header bytes) / 4-byte C enum.

    // The source scanner uses a fixed valid-symbol array during soft-line lookahead.
    static let paragraphInterruptSymbols: [Bool] = [
        false, false, false, false, true, false, true, true, true, true,
        true, true, true, true, true, true, true, true, true, true,
        false, false, false, false, false, true, true, true, false, false,
        true, false, true, true, true, true, true, false, false, false,
        false, false, false, false, false, true, false
    ]

    var openBlocks: ContiguousArray<Block> = []
    var state = 0
    var matched = 0
    var indentation = 0
    var column = 0
    var fencedCodeBlockDelimiterLength = 0
    var simulate = false

    /// Creates an empty block stack at the start of a document.
    public init() {}

    /// Serializes parser flags and the open block stack in the C scanner's byte layout.
    /// - Complexity: O(b), where b is the number of open blocks.
    public func serialize(into buffer: inout [UInt8]) {
        buffer.reserveCapacity(buffer.count + 5 + openBlocks.count * 4)
        buffer.append(UInt8(truncatingIfNeeded: state))
        buffer.append(UInt8(truncatingIfNeeded: matched))
        buffer.append(UInt8(truncatingIfNeeded: indentation))
        buffer.append(UInt8(truncatingIfNeeded: column))
        buffer.append(UInt8(truncatingIfNeeded: fencedCodeBlockDelimiterLength))
        for block in openBlocks {
            let raw = UInt32(block.rawValue)
            buffer.append(UInt8(truncatingIfNeeded: raw))
            buffer.append(UInt8(truncatingIfNeeded: raw >> 8))
            buffer.append(UInt8(truncatingIfNeeded: raw >> 16))
            buffer.append(UInt8(truncatingIfNeeded: raw >> 24))
        }
    }

    /// Restores a saved block stack; an empty state starts a new document.
    /// - Complexity: O(b), where b is the number of serialized blocks.
    public mutating func deserialize(_ bytes: ArraySlice<UInt8>) {
        self = Self()
        guard bytes.count >= 5 else { return }
        let base = bytes.startIndex
        state = Int(bytes[base])
        matched = Int(bytes[base + 1])
        indentation = Int(bytes[base + 2])
        column = Int(bytes[base + 3])
        fencedCodeBlockDelimiterLength = Int(bytes[base + 4])
        var offset = 5
        while offset + 4 <= bytes.count && openBlocks.count < Self.maximumBlocks {
            let raw =
                UInt32(bytes[base + offset]) | UInt32(bytes[base + offset + 1]) << 8
                | UInt32(bytes[base + offset + 2]) << 16 | UInt32(bytes[base + offset + 3]) << 24
            guard let block = Block(rawValue: Int(raw)) else {
                self = Self()
                return
            }
            openBlocks.append(block)
            offset += 4
        }
        if offset != bytes.count || matched > openBlocks.count { self = Self() }
    }

    /// Scans one offered external token, preserving state if no offered token is found.
    /// - Returns: Whether an offered token was recognized.
    /// - Complexity: O(n + b), where n is the lookahead length and b is the open block count.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count == Self.externalNames.count else { return false }
        var candidate = self
        candidate.simulate = false
        guard candidate.scanCore(&lexer, validSymbols: validSymbols),
            validSymbols[lexer.resultSymbol]
        else { return false }
        self = candidate
        return true
    }

    mutating func pushBlock(_ block: Block) -> Bool {
        guard openBlocks.count < Self.maximumBlocks else { return false }
        openBlocks.append(block)
        return true
    }

    mutating func markEnd(_ lexer: inout some ScannerLexer) {
        if !simulate { lexer.markEnd() }
    }

    // Tabs advance to the next four-column stop, as in the C scanner.
    @discardableResult mutating func advance(_ lexer: inout some ScannerLexer) -> Int {
        let size: Int
        if lexer.lookahead == 9 {
            size = 4 - column
            column = 0
        } else {
            size = 1
            column = (column + 1) % 4
        }
        lexer.advance(skip: false)
        return size
    }

    mutating func match(_ block: Block, _ lexer: inout some ScannerLexer) -> Bool {
        switch block {
            case .indentedCodeBlock:
                while indentation < 4 && (lexer.lookahead == 32 || lexer.lookahead == 9) {
                    indentation = (indentation + advance(&lexer)) & 0xFF
                }
                if indentation >= 4 && !Self.isNewline(lexer.lookahead) {
                    indentation -= 4
                    return true
                }
            case .listItem, .listItem1Indentation, .listItem2Indentation, .listItem3Indentation,
                .listItem4Indentation, .listItem5Indentation, .listItem6Indentation,
                .listItem7Indentation, .listItem8Indentation, .listItem9Indentation,
                .listItem10Indentation, .listItem11Indentation, .listItem12Indentation,
                .listItem13Indentation, .listItem14Indentation, .listItemMaxIndentation:
                let required = block.rawValue - Block.listItem.rawValue + 2
                while indentation < required && (lexer.lookahead == 32 || lexer.lookahead == 9) {
                    indentation = (indentation + advance(&lexer)) & 0xFF
                }
                if indentation >= required {
                    indentation -= required
                    return true
                }
                if Self.isNewline(lexer.lookahead) {
                    indentation = 0
                    return true
                }
            case .blockQuote:
                while lexer.lookahead == 32 || lexer.lookahead == 9 {
                    indentation = (indentation + advance(&lexer)) & 0xFF
                }
                if lexer.lookahead == 62 {
                    advance(&lexer)
                    indentation = 0
                    if lexer.lookahead == 32 || lexer.lookahead == 9 {
                        indentation = (indentation + advance(&lexer) - 1) & 0xFF
                    }
                    return true
                }
            case .fencedCodeBlock, .anonymous: return true
        }
        return false
    }

    static func isNewline(_ scalar: UInt32) -> Bool { scalar == 10 || scalar == 13 }
}
