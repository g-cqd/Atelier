import AtelierParser

extension PythonExternalScanner {
    mutating func scanStringPart(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], errorRecoveryMode: Bool
    ) -> Bool? {
        var advancedOnce = false
        if validSymbols[TokenType.escapeInterpolation.rawValue], let delimiter = delimiters.last,
            lexer.lookahead == 123 || lexer.lookahead == 125, !errorRecoveryMode, delimiter.isFormat
        {
            lexer.markEnd()
            let isLeftBrace = lexer.lookahead == 123
            lexer.advance(skip: false)
            advancedOnce = true
            if lexer.lookahead == (isLeftBrace ? 123 : 125) {
                lexer.advance(skip: false)
                lexer.markEnd()
                lexer.resultSymbol = TokenType.escapeInterpolation.rawValue
                return true
            }
            return false
        }

        guard validSymbols[TokenType.stringContent.rawValue], let delimiter = delimiters.last,
            !errorRecoveryMode
        else { return nil }
        let endCharacter = delimiter.endCharacter
        var hasContent = advancedOnce
        while lexer.lookahead != 0 {
            if (advancedOnce || lexer.lookahead == 123 || lexer.lookahead == 125) && delimiter.isFormat {
                lexer.markEnd()
                lexer.resultSymbol = TokenType.stringContent.rawValue
                return hasContent
            }
            if lexer.lookahead == 92 {
                if let result = scanBackslash(&lexer, delimiter: delimiter, hasContent: hasContent) {
                    return result
                }
                if delimiter.isRaw { continue }
            } else if lexer.lookahead == endCharacter {
                return scanClosingQuote(&lexer, delimiter: delimiter, hasContent: hasContent)
            } else if lexer.lookahead == 10 && hasContent && !delimiter.isTriple {
                return false
            }
            lexer.advance(skip: false)
            hasContent = true
        }
        return nil
    }

    private func scanBackslash(
        _ lexer: inout some ScannerLexer, delimiter: Delimiter, hasContent: Bool
    ) -> Bool? {
        if delimiter.isRaw {
            // Step over the backslash.
            lexer.advance(skip: false)
            // Step over any escaped quotes.
            if lexer.lookahead == delimiter.endCharacter || lexer.lookahead == 92 { lexer.advance(skip: false) }
            // Step over newlines
            if lexer.lookahead == 13 {
                lexer.advance(skip: false)
                if lexer.lookahead == 10 { lexer.advance(skip: false) }
            } else if lexer.lookahead == 10 {
                lexer.advance(skip: false)
            }
            return nil
        }
        if delimiter.isBytes {
            lexer.markEnd()
            lexer.advance(skip: false)
            if lexer.lookahead == 78 || lexer.lookahead == 117 || lexer.lookahead == 85 {
                // In bytes string, \N{...}, \uXXXX and \UXXXXXXXX are
                // not escape sequences
                // https://docs.python.org/3/reference/lexical_analysis.html#string-and-bytes-literals
                lexer.advance(skip: false)
                return nil
            }
            lexer.resultSymbol = TokenType.stringContent.rawValue
            return hasContent
        }
        lexer.markEnd()
        lexer.resultSymbol = TokenType.stringContent.rawValue
        return hasContent
    }

    private mutating func scanClosingQuote(
        _ lexer: inout some ScannerLexer, delimiter: Delimiter, hasContent: Bool
    ) -> Bool {
        if delimiter.isTriple {
            lexer.markEnd()
            lexer.advance(skip: false)
            if lexer.lookahead == delimiter.endCharacter {
                lexer.advance(skip: false)
                if lexer.lookahead == delimiter.endCharacter {
                    if hasContent {
                        lexer.resultSymbol = TokenType.stringContent.rawValue
                    } else {
                        lexer.advance(skip: false)
                        lexer.markEnd()
                        delimiters.removeLast()
                        lexer.resultSymbol = TokenType.stringEnd.rawValue
                        insideInterpolatedString = false
                    }
                    return true
                }
                lexer.markEnd()
                lexer.resultSymbol = TokenType.stringContent.rawValue
                return true
            }
            lexer.markEnd()
            lexer.resultSymbol = TokenType.stringContent.rawValue
            return true
        }
        if hasContent {
            lexer.resultSymbol = TokenType.stringContent.rawValue
        } else {
            lexer.advance(skip: false)
            delimiters.removeLast()
            lexer.resultSymbol = TokenType.stringEnd.rawValue
            insideInterpolatedString = false
        }
        lexer.markEnd()
        return true
    }

    mutating func scanStringStart(_ lexer: inout some ScannerLexer) -> Bool {
        var delimiter = Delimiter()
        var hasFlags = false
        while lexer.lookahead != 0 {
            if lexer.lookahead == 102 || lexer.lookahead == 70 || lexer.lookahead == 116 || lexer.lookahead == 84 {
                delimiter.setFormat()
            } else if lexer.lookahead == 114 || lexer.lookahead == 82 {
                delimiter.setRaw()
            } else if lexer.lookahead == 98 || lexer.lookahead == 66 {
                delimiter.setBytes()
            } else if lexer.lookahead != 117 && lexer.lookahead != 85 {
                break
            }
            hasFlags = true
            lexer.advance(skip: false)
        }

        if lexer.lookahead == 96 {
            guard delimiter.setEndCharacter(96) else { return false }
            lexer.advance(skip: false)
            lexer.markEnd()
        } else if lexer.lookahead == 39 || lexer.lookahead == 34 {
            let quote = lexer.lookahead
            guard delimiter.setEndCharacter(quote) else { return false }
            lexer.advance(skip: false)
            lexer.markEnd()
            if lexer.lookahead == quote {
                lexer.advance(skip: false)
                if lexer.lookahead == quote {
                    lexer.advance(skip: false)
                    lexer.markEnd()
                    delimiter.setTriple()
                }
            }
        }
        if delimiter.endCharacter != 0 {
            delimiters.append(delimiter)
            lexer.resultSymbol = TokenType.stringStart.rawValue
            insideInterpolatedString = delimiter.isFormat
            return true
        }
        if hasFlags { return false }
        return false
    }
}
