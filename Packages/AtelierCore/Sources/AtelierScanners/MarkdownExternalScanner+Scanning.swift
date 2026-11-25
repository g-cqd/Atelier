import AtelierParser

extension MarkdownExternalScanner {
    mutating func scanCore(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        if valid[Token.triggerError.rawValue] {
            lexer.resultSymbol = Token.error.rawValue
            return true
        }
        if valid[Token.closeBlock.rawValue] {
            state |= Self.stateCloseBlock
            lexer.resultSymbol = Token.closeBlock.rawValue
            return true
        }
        if lexer.isAtEnd {
            if valid[Token.eof.rawValue] {
                lexer.resultSymbol = Token.eof.rawValue
                return true
            }
            if !openBlocks.isEmpty {
                lexer.resultSymbol = Token.blockClose.rawValue
                if !simulate { openBlocks.removeLast() }
                return true
            }
            return false
        }
        if let result = scanPrefix(&lexer, validSymbols: valid) { return result }
        return scanLineEnding(&lexer, validSymbols: valid)
    }

    // The non-newline portion of scan is also used for one-level paragraph lookahead.
    mutating func scanPrefix(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool? {
        if state & Self.stateMatching == 0 {
            while lexer.lookahead == 32 || lexer.lookahead == 9 { indentation = (indentation + advance(&lexer)) & 0xFF }
            if valid[Token.indentedChunkStart.rawValue] && !valid[Token.noIndentedChunk.rawValue]
                && indentation >= 4 && !Self.isNewline(lexer.lookahead)
            {
                lexer.resultSymbol = Token.indentedChunkStart.rawValue
                guard simulate || pushBlock(.indentedCodeBlock) else { return false }
                indentation -= 4
                return true
            }
            switch lexer.lookahead {
                case 10, 13:
                    if valid[Token.blankLineStart.rawValue] {
                        lexer.resultSymbol = Token.blankLineStart.rawValue
                        return true
                    }
                case 96: return parseFencedCodeBlock(96, &lexer, validSymbols: valid)
                case 126: return parseFencedCodeBlock(126, &lexer, validSymbols: valid)
                case 42: return parseStar(&lexer, validSymbols: valid)
                case 95: return parseThematicBreakUnderscore(&lexer, validSymbols: valid)
                case 62: return parseBlockQuote(&lexer, validSymbols: valid)
                case 35: return parseAtxHeading(&lexer, validSymbols: valid)
                case 61: return parseSetextUnderline(&lexer, validSymbols: valid)
                case 43: return parsePlus(&lexer, validSymbols: valid)
                case 48 ... 57: return parseOrderedListMarker(&lexer, validSymbols: valid)
                case 45: return parseMinus(&lexer, validSymbols: valid)
                case 60: return parseHTMLBlock(&lexer, validSymbols: valid)
                default: break
            }
            if !Self.isNewline(lexer.lookahead) && valid[Token.pipeTableStart.rawValue] {
                return parsePipeTable(&lexer)
            }
        } else {
            var partialSuccess = false
            while matched < openBlocks.count {
                if matched == openBlocks.count - 1 && state & Self.stateCloseBlock != 0 {
                    if !partialSuccess { state &= ~Self.stateCloseBlock }
                    break
                }
                guard match(openBlocks[matched], &lexer) else {
                    if state & Self.stateWasSoftLineBreak != 0 { state &= ~Self.stateMatching }
                    break
                }
                partialSuccess = true
                matched += 1
            }
            if partialSuccess {
                if matched == openBlocks.count { state &= ~Self.stateMatching }
                lexer.resultSymbol = Token.blockContinuation.rawValue
                return true
            }
            if state & Self.stateWasSoftLineBreak == 0 && !openBlocks.isEmpty {
                lexer.resultSymbol = Token.blockClose.rawValue
                openBlocks.removeLast()
                if matched == openBlocks.count { state &= ~Self.stateMatching }
                return true
            }
        }
        return nil
    }

    mutating func scanLineEnding(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard
            (valid[Token.lineEnding.rawValue] || valid[Token.softLineEnding.rawValue]
                || valid[Token.pipeTableLineEnding.rawValue]) && Self.isNewline(lexer.lookahead)
        else { return false }
        if lexer.lookahead == 13 {
            advance(&lexer)
            if lexer.lookahead == 10 { advance(&lexer) }
        } else {
            advance(&lexer)
        }
        indentation = 0
        column = 0
        if state & Self.stateCloseBlock == 0
            && (valid[Token.softLineEnding.rawValue] || valid[Token.pipeTableLineEnding.rawValue])
        {
            lexer.markEnd()
            while lexer.lookahead == 32 || lexer.lookahead == 9 { indentation = (indentation + advance(&lexer)) & 0xFF }
            simulate = true
            let matchedTemp = matched
            matched = 0
            var oneWillBeMatched = false
            while matched < openBlocks.count {
                guard match(openBlocks[matched], &lexer) else { break }
                matched += 1
                oneWillBeMatched = true
            }
            let allWillBeMatched = matched == openBlocks.count
            if !lexer.isAtEnd && scanPrefix(&lexer, validSymbols: Self.paragraphInterruptSymbols) != true {
                matched = 0
                indentation = 0
                column = 0
                if oneWillBeMatched { state |= Self.stateMatching } else { state &= ~Self.stateMatching }
                guard valid[Token.pipeTableLineEnding.rawValue] else {
                    lexer.resultSymbol = Token.softLineEnding.rawValue
                    state |= Self.stateWasSoftLineBreak
                    return true
                }
                if allWillBeMatched {
                    lexer.resultSymbol = Token.pipeTableLineEnding.rawValue
                    return true
                }
            } else {
                matched = matchedTemp
            }
            indentation = 0
            column = 0
        }
        if valid[Token.lineEnding.rawValue] {
            matched = 0
            if !openBlocks.isEmpty { state |= Self.stateMatching } else { state &= ~Self.stateMatching }
            state &= ~Self.stateWasSoftLineBreak
            lexer.resultSymbol = Token.lineEnding.rawValue
            return true
        }
        return false
    }
}
