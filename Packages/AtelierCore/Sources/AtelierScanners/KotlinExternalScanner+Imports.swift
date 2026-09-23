// Port of fwcd/tree-sitter-kotlin/src/scanner.c at f3a1ea74304adad67164a0a6ffe729428748a7a7.
// Copyright (c) 2019 fwcd. Licensed under the MIT License.

import AtelierParser

private func isKotlinImportSpace(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isWhitespace == true
}

extension KotlinExternalScanner {
    func scanSafeNav(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.resultSymbol = TokenType.safeNav.rawValue
        lexer.markEnd()
        while isKotlinImportSpace(lexer.lookahead) { lexer.advance(skip: true) }
        guard lexer.lookahead == 63 else { return false }
        lexer.advance(skip: false)
        while isKotlinImportSpace(lexer.lookahead) { lexer.advance(skip: true) }
        guard lexer.lookahead == 46 else { return false }
        lexer.advance(skip: false)
        lexer.markEnd()
        return true
    }

    private func scanLineSep(_ lexer: inout some ScannerLexer) -> Bool {
        // Line Seps: [ CR, LF, CRLF ].
        var sawCR = false
        while true {
            switch lexer.lookahead {
                case 32, 9, 11:
                    lexer.advance(skip: false)
                case 10:
                    lexer.advance(skip: false)
                    return true
                case 13:
                    if sawCR { return true }
                    sawCR = true
                    lexer.advance(skip: false)
                default:
                    return sawCR
            }
        }
    }

    func scanImportListDelimiter(_ lexer: inout some ScannerLexer) -> Bool {
        // Import lists are terminated either by an empty line or a non import statement.
        lexer.resultSymbol = TokenType.importListDelimiter.rawValue
        lexer.markEnd()
        if lexer.isAtEnd { return true }
        guard scanLineSep(&lexer) else { return false }
        if scanLineSep(&lexer) {
            lexer.markEnd()
            return true
        }
        while true {
            switch lexer.lookahead {
                case 32, 9, 11: lexer.advance(skip: false)
                case 105: return !Self.scanForWord(&lexer, word: "mport")
                default: return true
            }
        }
    }

    // Scan a dot in import identifiers. A dot followed by a newline and
    // 'import' produces an ASI before the dot, preventing malformed imports
    // from bleeding into the next valid import.
    func scanImportDot(_ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == 46 else { return false }
        lexer.markEnd()
        lexer.advance(skip: false)
        var foundNewline = false
        while isKotlinImportSpace(lexer.lookahead) {
            if lexer.lookahead == 10 || lexer.lookahead == 13 { foundNewline = true }
            lexer.advance(skip: true)
        }
        if foundNewline && lexer.lookahead == 105 && Self.scanForWord(&lexer, word: "mport") {
            lexer.resultSymbol = TokenType.automaticSemicolon.rawValue
            return true
        }
        lexer.resultSymbol = TokenType.importDot.rawValue
        lexer.markEnd()
        return true
    }
}
