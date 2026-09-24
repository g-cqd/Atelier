import AtelierParser

extension PythonExternalScanner {
    mutating func scanUnchecked(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        let errorRecoveryMode =
            validSymbols[TokenType.stringContent.rawValue] && validSymbols[TokenType.indent.rawValue]
        let withinBrackets =
            validSymbols[TokenType.closeBrace.rawValue] || validSymbols[TokenType.closeParen.rawValue]
            || validSymbols[TokenType.closeBracket.rawValue]

        if let result = scanStringPart(&lexer, validSymbols: validSymbols, errorRecoveryMode: errorRecoveryMode) {
            return result
        }
        lexer.markEnd()
        guard let whitespace = scanWhitespace(&lexer, validSymbols: validSymbols) else { return false }
        if whitespace.foundEndOfLine
            && scanLineToken(
                &lexer, validSymbols: validSymbols, errorRecoveryMode: errorRecoveryMode,
                withinBrackets: withinBrackets, indentLength: whitespace.indentLength,
                firstCommentIndentLength: whitespace.firstCommentIndentLength
            )
        {
            return true
        }
        if whitespace.firstCommentIndentLength == -1 && validSymbols[TokenType.stringStart.rawValue] {
            return scanStringStart(&lexer)
        }
        return false
    }

    private func scanWhitespace(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool]
    ) -> (foundEndOfLine: Bool, indentLength: UInt16, firstCommentIndentLength: Int)? {
        var foundEndOfLine = false
        var indentLength: UInt16 = 0
        var firstCommentIndentLength = -1
        while true {
            if lexer.lookahead == 10 {
                foundEndOfLine = true
                indentLength = 0
                lexer.advance(skip: true)
            } else if lexer.lookahead == 32 {
                indentLength &+= 1
                lexer.advance(skip: true)
            } else if lexer.lookahead == 13 || lexer.lookahead == 12 {
                indentLength = 0
                lexer.advance(skip: true)
            } else if lexer.lookahead == 9 {
                indentLength &+= 8
                lexer.advance(skip: true)
            } else if lexer.lookahead == 35
                && (validSymbols[TokenType.indent.rawValue]
                    || validSymbols[TokenType.dedent.rawValue] || validSymbols[TokenType.newline.rawValue]
                    || validSymbols[TokenType.except.rawValue])
            {
                // If we haven't found an EOL yet,
                // then this is a comment after an expression:
                //   foo = bar # comment
                // Just return, since we don't want to generate an indent/dedent
                // token.
                if !foundEndOfLine { return nil }
                if firstCommentIndentLength == -1 { firstCommentIndentLength = Int(indentLength) }
                while lexer.lookahead != 0 && lexer.lookahead != 10 { lexer.advance(skip: true) }
                lexer.advance(skip: true)
                indentLength = 0
            } else if lexer.lookahead == 92 {
                lexer.advance(skip: true)
                if lexer.lookahead == 13 { lexer.advance(skip: true) }
                guard lexer.lookahead == 10 || lexer.isAtEnd else { return nil }
                lexer.advance(skip: true)
            } else if lexer.isAtEnd {
                indentLength = 0
                foundEndOfLine = true
                break
            } else {
                break
            }
        }
        return (foundEndOfLine, indentLength, firstCommentIndentLength)
    }

    private mutating func scanLineToken(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], errorRecoveryMode: Bool,
        withinBrackets: Bool, indentLength: UInt16, firstCommentIndentLength: Int
    ) -> Bool {
        if let currentIndentLength = indents.last {
            if validSymbols[TokenType.indent.rawValue] && indentLength > currentIndentLength {
                indents.append(indentLength)
                lexer.resultSymbol = TokenType.indent.rawValue
                return true
            }

            let nextTokenIsStringStart = lexer.lookahead == 34 || lexer.lookahead == 39 || lexer.lookahead == 96
            if (validSymbols[TokenType.dedent.rawValue]
                || (!validSymbols[TokenType.newline.rawValue]
                    && !(validSymbols[TokenType.stringStart.rawValue] && nextTokenIsStringStart)
                    && !withinBrackets))
                && indentLength < currentIndentLength && !insideInterpolatedString
                // Wait to create a dedent token until we've consumed any
                // comments
                // whose indentation matches the current block.
                && firstCommentIndentLength < Int(currentIndentLength)
            {
                indents.removeLast()
                lexer.resultSymbol = TokenType.dedent.rawValue
                return true
            }
        }
        if validSymbols[TokenType.newline.rawValue] && !errorRecoveryMode {
            lexer.resultSymbol = TokenType.newline.rawValue
            return true
        }
        return false
    }
}
