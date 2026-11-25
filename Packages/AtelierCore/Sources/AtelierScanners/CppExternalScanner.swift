// Port of tree-sitter/tree-sitter-cpp/src/scanner.c at
// 80f5bd82d3b4a1acf07f34a569d88a4a29f74c42 (after v0.23.4).
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

/// The external scanner for the pinned C++ grammar's raw strings.
public struct CppExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case rawStringDelimiter
        case rawStringContent
    }

    // The spec limits delimiters to 16 chars.
    private static let maximumDelimiterLength = 16

    /// The bundled C++ grammar's `externals`, in order.
    public static let externalNames = ["raw_string_delimiter", "raw_string_content"]

    private var delimiter: [UInt32] = []

    /// Creates a scanner with no open raw string.
    public init() {}

    /// Writes each delimiter scalar as the C scanner's four-byte `wchar_t`.
    public func serialize(into buffer: inout [UInt8]) {
        for scalar in delimiter {
            buffer.append(UInt8(truncatingIfNeeded: scalar))
            buffer.append(UInt8(truncatingIfNeeded: scalar >> 8))
            buffer.append(UInt8(truncatingIfNeeded: scalar >> 16))
            buffer.append(UInt8(truncatingIfNeeded: scalar >> 24))
        }
    }

    /// Restores a C scanner delimiter; empty or malformed data resets it.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        delimiter.removeAll(keepingCapacity: true)
        guard state.count.isMultiple(of: 4), state.count <= Self.maximumDelimiterLength * 4 else { return }
        delimiter.reserveCapacity(state.count / 4)
        var index = state.startIndex
        while index < state.endIndex {
            let scalar =
                UInt32(state[index]) | UInt32(state[index + 1]) << 8
                | UInt32(state[index + 2]) << 16 | UInt32(state[index + 3]) << 24
            delimiter.append(scalar)
            index += 4
        }
    }

    private static func isSpace(_ scalar: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(scalar) else { return false }
        return scalar.properties.isWhitespace
    }

    private mutating func scanRawStringDelimiter(_ lexer: inout some ScannerLexer) -> Bool {
        if !delimiter.isEmpty {
            // Closing delimiter: must exactly match the opening delimiter.
            // We already checked this when scanning content, but this is how we
            // know when to stop. We can't stop at ", because R"""hello""" is valid.
            for scalar in delimiter {
                guard lexer.lookahead == scalar else { return false }
                lexer.advance(skip: false)
            }
            delimiter.removeAll(keepingCapacity: true)
            return true
        }

        // Opening delimiter: record the d-char-sequence up to (.
        // d-char is any basic character except parens, backslashes, and spaces.
        var opening: [UInt32] = []
        opening.reserveCapacity(Self.maximumDelimiterLength)
        while true {
            guard opening.count < Self.maximumDelimiterLength, !lexer.isAtEnd,
                lexer.lookahead != 0x5C, !Self.isSpace(lexer.lookahead)
            else { return false }
            if lexer.lookahead == 0x28 {
                // Rather than create a token for an empty delimiter, we fail and
                // let the grammar fall back to a delimiter-less rule.
                guard !opening.isEmpty else { return false }
                delimiter = opening
                return true
            }
            opening.append(lexer.lookahead)
            lexer.advance(skip: false)
        }
    }

    private func scanRawStringContent(_ lexer: inout some ScannerLexer) -> Bool {
        // The progress made through the delimiter since the last ')'.
        // The delimiter may not contain ')' so a single counter suffices.
        var delimiterIndex = -1
        while true {
            // If we hit EOF, consider the content to terminate there.
            // This forms an incomplete raw_string_literal, and models the code well.
            if lexer.isAtEnd {
                lexer.markEnd()
                return true
            }
            if delimiterIndex >= 0 {
                if delimiterIndex == delimiter.count {
                    if lexer.lookahead == 0x22 { return true }
                    delimiterIndex = -1
                } else if lexer.lookahead == delimiter[delimiterIndex] {
                    delimiterIndex += 1
                } else {
                    delimiterIndex = -1
                }
            }
            if delimiterIndex == -1 && lexer.lookahead == 0x29 {
                // The content doesn't include the )delimiter" part.
                // We must still scan through it, but exclude it from the token.
                lexer.markEnd()
                delimiterIndex = 0
            }
            lexer.advance(skip: false)
        }
    }

    /// Recognizes a delimiter or its content when that token is offered.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        if validSymbols[TokenType.rawStringDelimiter.rawValue] && validSymbols[TokenType.rawStringContent.rawValue] {
            // We're in error recovery.
            return false
        }
        // No skipping leading whitespace: raw-string grammar is space-sensitive.
        if validSymbols[TokenType.rawStringDelimiter.rawValue] {
            lexer.resultSymbol = TokenType.rawStringDelimiter.rawValue
            return scanRawStringDelimiter(&lexer)
        }
        if validSymbols[TokenType.rawStringContent.rawValue] {
            lexer.resultSymbol = TokenType.rawStringContent.rawValue
            return scanRawStringContent(&lexer)
        }
        return false
    }
}
