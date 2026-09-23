// Port of tree-sitter/tree-sitter-ruby/src/scanner.c, v0.23.1,
// commit 71bd32fb7607035768799732addba884a37a6210.
// The MIT License (MIT)
// Copyright (c) 2016 Rob Rix
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

/// The external scanner for the bundled Ruby grammar.
///
/// A value keeps open literal and heredoc delimiters across parser calls.
public struct RubyExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case lineBreak
        case noLineBreak
        case simpleSymbol
        case stringStart
        case symbolStart
        case subshellStart
        case regexStart
        case stringArrayStart
        case symbolArrayStart
        case heredocBodyStart
        case stringContent
        case heredocContent
        case stringEnd
        case heredocBodyEnd
        case heredocStart
        case forwardSlash
        case blockAmpersand
        case splatStar
        case unaryMinus
        case unaryMinusNum
        case binaryMinus
        case binaryStar
        case singletonClassLeftAngleLeftAngle
        case hashKeySymbol
        case identifierSuffix
        case constantSuffix
        case hashSplatStarStar
        case binaryStarStar
        case elementReferenceBracket
        case shortInterpolation
        case none
    }

    struct Literal {
        var type: TokenType = .none
        var openDelimiter: UInt32 = 0
        var closeDelimiter: UInt32 = 0
        var nestingDepth = 0
        var allowsInterpolation = false
    }

    struct Heredoc {
        var word: [UInt8] = []
        var endWordIndentationAllowed = false
        var allowsInterpolation = false
        var started = false
    }

    /// The bundled grammar's `externals`, in order.
    public static let externalNames = [
        "_line_break", "_no_line_break", "simple_symbol", "_string_start", "_symbol_start",
        "_subshell_start", "_regex_start", "_string_array_start", "_symbol_array_start",
        "_heredoc_body_start", "string_content", "heredoc_content", "_string_end",
        "heredoc_end", "heredoc_beginning", "/", "_block_ampersand", "_splat_star",
        "_unary_minus", "_unary_minus_num", "_binary_minus", "_binary_star",
        "_singleton_class_left_angle_left_langle", "hash_key_symbol", "_identifier_suffix",
        "_constant_suffix", "_hash_splat_star_star", "_binary_star_star",
        "_element_reference_bracket", "_short_interpolation"
    ]

    var hasLeadingWhitespace = false
    var literalStack: [Literal] = []
    var openHeredocs: [Heredoc] = []

    /// Creates a scanner without open literals or heredocs.
    public init() {}

    /// Appends the C scanner's compact delimiter state when it fits the parser's state buffer.
    /// - Complexity: O(l + h + w), for l literals, h heredocs, and w heredoc word bytes.
    public func serialize(into buffer: inout [UInt8]) {
        guard literalStack.count <= UInt8.max, openHeredocs.count <= UInt8.max else { return }
        let literalBytes = 1 + literalStack.count * 5 + 1
        guard literalBytes < maximumSerializedScannerStateSize else { return }
        var total = literalBytes
        for heredoc in openHeredocs {
            guard heredoc.word.count <= UInt8.max else { return }
            total += 4 + heredoc.word.count
            guard total <= maximumSerializedScannerStateSize else { return }
        }
        for literal in literalStack {
            guard literal.nestingDepth <= UInt8.max, literal.nestingDepth >= 0 else { return }
        }

        buffer.reserveCapacity(buffer.count + total)
        buffer.append(UInt8(literalStack.count))
        for literal in literalStack {
            buffer.append(UInt8(literal.type.rawValue))
            buffer.append(UInt8(truncatingIfNeeded: literal.openDelimiter))
            buffer.append(UInt8(truncatingIfNeeded: literal.closeDelimiter))
            buffer.append(UInt8(literal.nestingDepth))
            buffer.append(literal.allowsInterpolation ? 1 : 0)
        }
        buffer.append(UInt8(openHeredocs.count))
        for heredoc in openHeredocs {
            buffer.append(heredoc.endWordIndentationAllowed ? 1 : 0)
            buffer.append(heredoc.allowsInterpolation ? 1 : 0)
            buffer.append(heredoc.started ? 1 : 0)
            buffer.append(UInt8(heredoc.word.count))
            buffer.append(contentsOf: heredoc.word)
        }
    }

    /// Restores a serialized state; empty or malformed state resets the scanner.
    /// - Complexity: O(n), where n is the number of state bytes.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        hasLeadingWhitespace = false
        literalStack.removeAll(keepingCapacity: true)
        openHeredocs.removeAll(keepingCapacity: true)
        guard !state.isEmpty, state.count <= maximumSerializedScannerStateSize else { return }

        var index = state.startIndex
        func read() -> UInt8? {
            guard index < state.endIndex else { return nil }
            defer { index = state.index(after: index) }
            return state[index]
        }
        guard let literalCount = read() else { return }
        var literals: [Literal] = []
        literals.reserveCapacity(Int(literalCount))
        for _ in 0 ..< literalCount {
            guard let typeByte = read(), let type = TokenType(rawValue: Int(typeByte)),
                let open = read(), let close = read(), let depth = read(), let interpolation = read()
            else { return }
            switch type {
                case .stringStart, .symbolStart, .subshellStart, .regexStart, .stringArrayStart, .symbolArrayStart:
                    break
                default:
                    return
            }
            guard depth > 0 else { return }
            literals.append(
                Literal(
                    type: type, openDelimiter: UInt32(open), closeDelimiter: UInt32(close),
                    nestingDepth: Int(depth), allowsInterpolation: interpolation != 0
                ))
        }
        guard let heredocCount = read() else { return }
        var heredocs: [Heredoc] = []
        heredocs.reserveCapacity(Int(heredocCount))
        for _ in 0 ..< heredocCount {
            guard let indentation = read(), let interpolation = read(), let started = read(), let wordCount = read(),
                wordCount > 0, state.distance(from: index, to: state.endIndex) >= Int(wordCount)
            else { return }
            let end = state.index(index, offsetBy: Int(wordCount))
            heredocs.append(
                Heredoc(
                    word: Array(state[index ..< end]), endWordIndentationAllowed: indentation != 0,
                    allowsInterpolation: interpolation != 0, started: started != 0
                ))
            index = end
        }
        guard index == state.endIndex else { return }
        literalStack = literals
        openHeredocs = heredocs
    }

    /// Scans one offered external token from the lexer's current position.
    /// - Returns: Whether the scanner recognized a token offered by `validSymbols`.
    /// - Complexity: O(n), where n is the number of examined input scalars.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        hasLeadingWhitespace = false
        var trial = self
        guard trial.scanUnchecked(&lexer, validSymbols: validSymbols) else { return false }
        // The upstream scanner can report a symbol that its caller did not offer.
        guard validSymbols.indices.contains(lexer.resultSymbol), validSymbols[lexer.resultSymbol] else { return false }
        self = trial
        return true
    }

    private mutating func scanUnchecked(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        // Contents of literals, which match any character except for some close delimiter
        if !validSymbols[TokenType.stringStart.rawValue] {
            if validSymbols[TokenType.stringContent.rawValue] || validSymbols[TokenType.stringEnd.rawValue],
                !literalStack.isEmpty
            {
                return scanLiteralContent(&lexer)
            }
            if validSymbols[TokenType.heredocContent.rawValue] || validSymbols[TokenType.heredocBodyEnd.rawValue],
                !openHeredocs.isEmpty
            {
                return scanHeredocContent(&lexer)
            }
        }

        // Whitespace
        lexer.resultSymbol = TokenType.none.rawValue
        guard scanWhitespace(&lexer, validSymbols: validSymbols) else { return false }
        if lexer.resultSymbol != TokenType.none.rawValue { return true }
        return scanToken(&lexer, validSymbols: validSymbols)
    }
}
