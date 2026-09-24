// Port of tree-sitter/tree-sitter-bash/src/scanner.c at
// a06c2e4415e9bc0346c6b86d401879ffb44058f7 (v0.25.1).
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

/// The stateful external scanner for the pinned Bash grammar.
public struct BashExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case heredocStart, simpleHeredocBody, heredocBodyBeginning, heredocContent, heredocEnd
        case fileDescriptor, emptyValue, concat, variableName, testOperator, regex, regexNoSlash
        case regexNoSpace, expansionWord, extglobPattern, bareDollar, braceStart, immediateDoubleHash
        case expansionSymHash, expansionSymBang, expansionSymEqual, closingBrace, closingBracket
        case heredocArrow, heredocArrowDash, newline, openingParen, esac, errorRecovery
    }

    struct Heredoc: Sendable {
        var isRaw = false
        var started = false
        var allowsIndent = false
        var delimiter: [UInt8] = []
        var currentLeadingWord: [UInt8] = []
    }

    var lastGlobParenDepth: UInt8 = 0
    var extWasInDoubleQuote = false
    var extSawOutsideQuote = false
    var heredocs: [Heredoc] = []

    /// The externals of the bundled Bash grammar, in grammar order. The newline is the pattern `/\n/`, which the tables
    /// name by its source: a backslash and an `n`.
    public static let externalNames = [
        "heredoc_start", "simple_heredoc_body", "_heredoc_body_beginning", "heredoc_content",
        "heredoc_end", "file_descriptor", "_empty_value", "_concat", "variable_name", "test_operator",
        "regex", "_regex_no_slash", "_regex_no_space", "_expansion_word", "extglob_pattern",
        "_bare_dollar", "_brace_start", "_immediate_double_hash", "_external_expansion_sym_hash",
        "_external_expansion_sym_bang", "_external_expansion_sym_equal", "}", "]", "<<", "<<-",
        "\\n", "(", "esac", "__error_recovery"
    ]

    /// Creates a scanner with no pending heredocs or glob context.
    public init() {}

    /// Appends the C scanner's state format, or nothing if the state exceeds tree-sitter's limit.
    /// - Complexity: O(n), where n is the total delimiter length.
    public func serialize(into buffer: inout [UInt8]) {
        guard heredocs.count <= UInt8.max else { return }
        var size = 4
        for heredoc in heredocs {
            guard heredoc.delimiter.count < maximumSerializedScannerStateSize - size - 7 else { return }
            size += 7 + heredoc.delimiter.count
        }
        buffer.reserveCapacity(buffer.count + size)
        buffer.append(lastGlobParenDepth)
        buffer.append(extWasInDoubleQuote ? 1 : 0)
        buffer.append(extSawOutsideQuote ? 1 : 0)
        buffer.append(UInt8(heredocs.count))
        for heredoc in heredocs {
            buffer.append(heredoc.isRaw ? 1 : 0)
            buffer.append(heredoc.started ? 1 : 0)
            buffer.append(heredoc.allowsIndent ? 1 : 0)
            let count = UInt32(heredoc.delimiter.count)
            buffer.append(UInt8(truncatingIfNeeded: count))
            buffer.append(UInt8(truncatingIfNeeded: count >> 8))
            buffer.append(UInt8(truncatingIfNeeded: count >> 16))
            buffer.append(UInt8(truncatingIfNeeded: count >> 24))
            buffer.append(contentsOf: heredoc.delimiter)
        }
    }

    /// Restores a serialized state; empty or malformed state resets the scanner.
    /// - Complexity: O(n), where n is the state length.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        self = Self()
        guard !state.isEmpty, state.count <= maximumSerializedScannerStateSize, state.count >= 4 else { return }
        let count = Int(state[state.startIndex + 3])
        var index = state.startIndex + 4
        var decoded: [Heredoc] = []
        decoded.reserveCapacity(count)
        for _ in 0 ..< count {
            guard index + 7 <= state.endIndex else { return }
            let length = Int(
                UInt32(state[index + 3]) | UInt32(state[index + 4]) << 8
                    | UInt32(state[index + 5]) << 16 | UInt32(state[index + 6]) << 24)
            guard length <= state.endIndex - index - 7 else { return }
            decoded.append(
                Heredoc(
                    isRaw: state[index] != 0, started: state[index + 1] != 0,
                    allowsIndent: state[index + 2] != 0,
                    delimiter: Array(state[index + 7 ..< index + 7 + length])
                ))
            index += 7 + length
        }
        guard index == state.endIndex else { return }
        lastGlobParenDepth = state[state.startIndex]
        extWasInDoubleQuote = state[state.startIndex + 1] != 0
        extSawOutsideQuote = state[state.startIndex + 2] != 0
        heredocs = decoded
    }

    /// Scans one external token offered by the parser, preserving state on decline.
    /// - Complexity: O(n), where n is the number of examined input scalars.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        var trial = self
        guard trial.scanUnchecked(&lexer, validSymbols: validSymbols),
            validSymbols.indices.contains(lexer.resultSymbol), validSymbols[lexer.resultSymbol]
        else { return false }
        self = trial
        return true
    }

    static func advance(_ lexer: inout some ScannerLexer) { lexer.advance(skip: false) }
    static func skip(_ lexer: inout some ScannerLexer) { lexer.advance(skip: true) }
    static func emit(_ token: TokenType, _ lexer: inout some ScannerLexer) {
        lexer.resultSymbol = token.rawValue
    }
}

extension Array where Element == Bool {
    subscript(_ token: BashExternalScanner.TokenType) -> Bool {
        indices.contains(token.rawValue) && self[token.rawValue]
    }
}
