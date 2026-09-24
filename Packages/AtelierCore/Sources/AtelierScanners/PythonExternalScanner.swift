// Port of tree-sitter/tree-sitter-python/src/scanner.c at
// commit 26855eabccb19c6abf499fbc5b8dc7cc9ab8bc64.
// MIT License
// Copyright (c) 2016 Max Brunsfeld
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

/// The external scanner for the bundled Python grammar.
///
/// A value holds the indentation stack and open string delimiters between parser calls.
public struct PythonExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case newline
        case indent
        case dedent
        case stringStart
        case stringContent
        case escapeInterpolation
        case stringEnd
        case comment
        case closeParen
        case closeBracket
        case closeBrace
        case except
    }

    struct Delimiter: Equatable {
        private static let singleQuote: UInt8 = 1 << 0
        private static let doubleQuote: UInt8 = 1 << 1
        private static let backQuote: UInt8 = 1 << 2
        private static let raw: UInt8 = 1 << 3
        private static let format: UInt8 = 1 << 4
        private static let triple: UInt8 = 1 << 5
        private static let bytes: UInt8 = 1 << 6

        var flags: UInt8 = 0

        var isFormat: Bool { flags & Self.format != 0 }
        var isRaw: Bool { flags & Self.raw != 0 }
        var isTriple: Bool { flags & Self.triple != 0 }
        var isBytes: Bool { flags & Self.bytes != 0 }

        var endCharacter: UInt32 {
            if flags & Self.singleQuote != 0 { return 39 }
            if flags & Self.doubleQuote != 0 { return 34 }
            if flags & Self.backQuote != 0 { return 96 }
            return 0
        }

        mutating func setFormat() { flags |= Self.format }
        mutating func setRaw() { flags |= Self.raw }
        mutating func setTriple() { flags |= Self.triple }
        mutating func setBytes() { flags |= Self.bytes }

        mutating func setEndCharacter(_ character: UInt32) -> Bool {
            switch character {
                case 39: flags |= Self.singleQuote
                case 34: flags |= Self.doubleQuote
                case 96: flags |= Self.backQuote
                default: return false
            }
            return true
        }
    }

    /// The bundled grammar's externals, in grammar order.
    public static let externalNames = [
        "_newline", "_indent", "_dedent", "string_start", "_string_content", "escape_interpolation",
        "string_end", "comment", "]", ")", "}", "except"
    ]

    var indents: [UInt16] = [0]
    var delimiters: [Delimiter] = []
    var insideInterpolatedString = false

    /// Creates a scanner with a zero indentation baseline and no open strings.
    public init() {}

    /// Scans one parser-offered token, preserving state if no token is returned.
    /// - Returns: Whether the scanner emitted an offered token.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        var trial = self
        guard trial.scanUnchecked(&lexer, validSymbols: validSymbols) else { return false }
        guard validSymbols.indices.contains(lexer.resultSymbol), validSymbols[lexer.resultSymbol] else { return false }
        self = trial
        return true
    }

    /// Appends the C scanner's compact delimiter and indentation state, within the parser's byte limit.
    /// - Complexity: O(d + i), where d is the number of delimiters and i is the number of indent levels.
    public func serialize(into buffer: inout [UInt8]) {
        let limit = maximumSerializedScannerStateSize
        guard buffer.count + 2 <= limit else { return }
        buffer.append(insideInterpolatedString ? 1 : 0)
        let delimiterCount = min(delimiters.count, Int(UInt8.max), limit - buffer.count - 1)
        buffer.append(UInt8(delimiterCount))
        for delimiter in delimiters.prefix(delimiterCount) { buffer.append(delimiter.flags) }
        for indent in indents.dropFirst() {
            guard buffer.count + 2 <= limit else { break }
            buffer.append(UInt8(truncatingIfNeeded: indent))
            buffer.append(UInt8(truncatingIfNeeded: indent >> 8))
        }
    }

    /// Restores state from the C format; an empty or malformed state resets the scanner.
    /// - Complexity: O(n), where n is the number of state bytes.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        indents = [0]
        delimiters.removeAll(keepingCapacity: true)
        insideInterpolatedString = false
        guard !state.isEmpty else { return }
        guard state.count >= 2, state.count <= maximumSerializedScannerStateSize else { return }
        let start = state.startIndex
        let delimiterCount = Int(state[start + 1])
        guard state.count >= 2 + delimiterCount else { return }
        insideInterpolatedString = state[start] != 0
        delimiters.reserveCapacity(delimiterCount)
        for index in (start + 2) ..< (start + 2 + delimiterCount) {
            delimiters.append(Delimiter(flags: state[index]))
        }
        var index = start + 2 + delimiterCount
        while index + 1 < state.endIndex {
            indents.append(UInt16(state[index]) | UInt16(state[index + 1]) << 8)
            index += 2
        }
    }
}
