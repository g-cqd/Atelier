// Port of fwcd/tree-sitter-kotlin/src/scanner.c at f3a1ea74304adad67164a0a6ffe729428748a7a7.
// The MIT License (MIT)
// Copyright (c) 2019 fwcd
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
// to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of
// the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
// TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

public import AtelierParser

/// The external tokens and string delimiter state of the bundled Kotlin grammar.
public struct KotlinExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case automaticSemicolon
        case importListDelimiter
        case safeNav
        case multilineComment
        case stringStart
        case stringEnd
        case stringContent
        case primaryConstructorKeyword
        case importDot
    }

    /// The external token names in the order of Kotlin's bundled `grammar.json`.
    public static let externalNames = [
        "_automatic_semicolon", "_import_list_delimiter", "safe_nav", "multiline_comment", "_string_start",
        "_string_end", "string_content", "_primary_constructor_keyword", "_import_dot"
    ]

    // We use a stack to keep track of the string delimiters. A triple quote is stored as '"' + 1.
    var delimiters: [UInt8] = []

    /// Creates a scanner with no open string delimiters.
    public init() {}

    /// Scans the next token offered by the parser, preserving the C scanner's precedence.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        if validSymbols[TokenType.automaticSemicolon.rawValue] {
            let found = scanAutomaticSemicolon(&lexer, validSymbols: validSymbols)
            if !found && validSymbols[TokenType.safeNav.rawValue] && lexer.lookahead == 63 {
                return scanSafeNav(&lexer)
            }
            // If we fail to find an automatic semicolon, it's still possible that we may
            // want to lex a string or comment later.
            if found { return validSymbols[lexer.resultSymbol] }
        }

        // Match dots in import identifiers, refusing dots that would cause
        // malformed imports to bleed into subsequent import statements.
        if validSymbols[TokenType.importDot.rawValue], scanImportDot(&lexer) {
            return validSymbols[lexer.resultSymbol]
        }

        // Match 'constructor' keyword for primary constructors when on the same line
        // (the cross-newline case is handled inside scan_automatic_semicolon).
        if validSymbols[TokenType.primaryConstructorKeyword.rawValue] && !validSymbols[TokenType.stringContent.rawValue]
        {
            while Self.isSpace(lexer.lookahead) { lexer.advance(skip: true) }
            if lexer.lookahead == 99 && Self.scanConstructorKeyword(&lexer) { return true }
        }

        if validSymbols[TokenType.importListDelimiter.rawValue] { return scanImportListDelimiter(&lexer) }
        return scanStringAndTrailingTokens(&lexer, validSymbols: validSymbols)
    }

    private mutating func scanStringAndTrailingTokens(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool]
    ) -> Bool {
        // Content or end.
        if validSymbols[TokenType.stringContent.rawValue] {
            let previousDelimiter = delimiters.last
            if scanStringContent(&lexer) {
                guard validSymbols[lexer.resultSymbol] else {
                    // STRING_END pops one delimiter; preserve the state when the parser did not offer it.
                    if let previousDelimiter { delimiters.append(previousDelimiter) }
                    return false
                }
                return true
            }
        }

        // A string might follow after some whitespace, so we can't lookahead
        // until we get rid of it.
        while Self.isSpace(lexer.lookahead) { lexer.advance(skip: true) }
        if validSymbols[TokenType.stringStart.rawValue], scanStringStart(&lexer) {
            lexer.resultSymbol = TokenType.stringStart.rawValue
            return true
        }
        if validSymbols[TokenType.multilineComment.rawValue], scanMultilineComment(&lexer) { return true }
        if validSymbols[TokenType.safeNav.rawValue] { return scanSafeNav(&lexer) }
        return false
    }

    /// Appends one byte per open delimiter, up to the parser's state limit.
    public func serialize(into buffer: inout [UInt8]) {
        buffer.append(contentsOf: delimiters)
    }

    /// Restores the delimiter stack; empty input clears any open string.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        delimiters = Array(state.prefix(maximumSerializedScannerStateSize))
    }

    private static func isSpace(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.isWhitespace == true
    }

    // Test for any identifier character other than the first character.
    // This is meant to match the regexp [\p{L}_\p{Nd}]
    // as found in '_alpha_identifier' (see grammar.js).
    private static func isWordChar(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil || value == 95
    }

    // Scan for [the end of] a nonempty alphanumeric identifier or
    // alphanumeric keyword (including '_').
    static func scanForWord(_ lexer: inout some ScannerLexer, word: String) -> Bool {
        lexer.advance(skip: true)
        for byte in word.utf8 {
            if lexer.lookahead != UInt32(byte) { return false }
            lexer.advance(skip: true)
        }
        return !isWordChar(lexer.lookahead)
    }

    // Check if a sequence of characters matches the given word and is followed
    // by a non-word character. Uses skip() so characters are not included in
    // the current token.
    static func checkWord(_ lexer: inout some ScannerLexer, word: String) -> Bool {
        for byte in word.utf8 {
            if lexer.lookahead != UInt32(byte) { return false }
            lexer.advance(skip: true)
        }
        return !isWordChar(lexer.lookahead)
    }

    // Check if the current position has a visibility modifier (public, private,
    // protected, internal) followed by horizontal whitespace and "constructor".
    // Uses skip() — safe to call speculatively since no token boundary is changed.
    static func checkModifierThenConstructor(_ lexer: inout some ScannerLexer) -> Bool {
        // Buffer the first word to identify the modifier.
        var word: InlineArray<19, UInt8> = .init(repeating: 0)
        var length = 0
        while isWordChar(lexer.lookahead) && length < 19 {
            guard let byte = UInt8(exactly: lexer.lookahead) else { return false }
            word[length] = byte
            length += 1
            lexer.advance(skip: true)
        }
        func matches(_ candidate: String) -> Bool {
            guard candidate.utf8.count == length else { return false }
            for (index, byte) in candidate.utf8.enumerated() where word[index] != byte { return false }
            return true
        }
        guard matches("public") || matches("private") || matches("protected") || matches("internal") else {
            return false
        }
        // Skip horizontal whitespace (not newlines).
        while lexer.lookahead == 32 || lexer.lookahead == 9 { lexer.advance(skip: true) }
        return checkWord(&lexer, word: "constructor")
    }

    static func scanConstructorKeyword(_ lexer: inout some ScannerLexer) -> Bool {
        for byte in "constructor".utf8 {
            if lexer.lookahead != UInt32(byte) { return false }
            lexer.advance(skip: false)
        }
        guard !isWordChar(lexer.lookahead) else { return false }
        lexer.resultSymbol = TokenType.primaryConstructorKeyword.rawValue
        lexer.markEnd()
        return true
    }
}
