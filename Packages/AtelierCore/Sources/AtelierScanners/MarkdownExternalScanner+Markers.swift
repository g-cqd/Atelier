import AtelierParser

extension MarkdownExternalScanner {
    mutating func parseFencedCodeBlock(
        _ delimiter: UInt32, _ lexer: inout some ScannerLexer, validSymbols valid: [Bool]
    ) -> Bool {
        // Count the number of backticks or tildes.
        var level = 0
        while lexer.lookahead == delimiter {
            advance(&lexer)
            level = (level + 1) & 0xFF
        }
        markEnd(&lexer)
        let end = delimiter == 96 ? Token.fencedCodeBlockEndBacktick : .fencedCodeBlockEndTilde
        let start = delimiter == 96 ? Token.fencedCodeBlockStartBacktick : .fencedCodeBlockStartTilde
        // A closing fence takes precedence when its length reaches the opening fence.
        if valid[end.rawValue] && indentation < 4 && level >= fencedCodeBlockDelimiterLength {
            while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
            if Self.isNewline(lexer.lookahead) {
                fencedCodeBlockDelimiterLength = 0
                lexer.resultSymbol = end.rawValue
                return true
            }
        }
        if valid[start.rawValue] && level >= 3 {
            var infoStringHasBacktick = false
            if delimiter == 96 {
                while !Self.isNewline(lexer.lookahead) && !lexer.isAtEnd {
                    if lexer.lookahead == 96 {
                        infoStringHasBacktick = true
                        break
                    }
                    advance(&lexer)
                }
            }
            if !infoStringHasBacktick {
                guard simulate || pushBlock(.fencedCodeBlock) else { return false }
                lexer.resultSymbol = start.rawValue
                fencedCodeBlockDelimiterLength = level & 0xFF
                indentation = 0
                return true
            }
        }
        return false
    }

    mutating func parseStar(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        advance(&lexer)
        markEnd(&lexer)
        var starCount = 1
        var extraIndentation = 0
        while true {
            if lexer.lookahead == 42 {
                if starCount == 1 && extraIndentation >= 1 && valid[Token.listMarkerStar.rawValue] {
                    markEnd(&lexer)
                }
                starCount += 1
                advance(&lexer)
            } else if lexer.lookahead == 32 || lexer.lookahead == 9 {
                if starCount == 1 {
                    extraIndentation = (extraIndentation + advance(&lexer)) & 0xFF
                } else {
                    advance(&lexer)
                }
            } else {
                break
            }
        }
        let lineEnd = Self.isNewline(lexer.lookahead)
        var dontInterrupt = false
        if starCount == 1 && lineEnd {
            extraIndentation = 1
            dontInterrupt = matched == openBlocks.count
        }
        let thematicBreak = starCount >= 3 && lineEnd
        let listMarkerStar = starCount >= 1 && extraIndentation >= 1
        if valid[Token.thematicBreak.rawValue] && thematicBreak && indentation < 4 {
            lexer.resultSymbol = Token.thematicBreak.rawValue
            markEnd(&lexer)
            indentation = 0
            return true
        }
        let listToken: Token = dontInterrupt ? .listMarkerStarDontInterrupt : .listMarkerStar
        if valid[listToken.rawValue] && listMarkerStar {
            if starCount == 1 { markEnd(&lexer) }
            extraIndentation -= 1
            if extraIndentation <= 3 {
                extraIndentation = (extraIndentation + indentation) & 0xFF
                indentation = 0
            } else {
                let temp = indentation
                indentation = extraIndentation
                extraIndentation = temp
            }
            guard let block = Block(rawValue: Block.listItem.rawValue + extraIndentation),
                simulate || pushBlock(block)
            else { return false }
            lexer.resultSymbol = listToken.rawValue
            return true
        }
        return false
    }

    mutating func parseThematicBreakUnderscore(
        _ lexer: inout some ScannerLexer, validSymbols valid: [Bool]
    ) -> Bool {
        advance(&lexer)
        markEnd(&lexer)
        var underscoreCount = 1
        while true {
            if lexer.lookahead == 95 {
                underscoreCount += 1
                advance(&lexer)
            } else if lexer.lookahead == 32 || lexer.lookahead == 9 {
                advance(&lexer)
            } else {
                break
            }
        }
        if underscoreCount >= 3 && Self.isNewline(lexer.lookahead) && valid[Token.thematicBreak.rawValue] {
            lexer.resultSymbol = Token.thematicBreak.rawValue
            markEnd(&lexer)
            indentation = 0
            return true
        }
        return false
    }

    mutating func parseBlockQuote(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard valid[Token.blockQuoteStart.rawValue] else { return false }
        advance(&lexer)
        indentation = 0
        if lexer.lookahead == 32 || lexer.lookahead == 9 { indentation = (indentation + advance(&lexer) - 1) & 0xFF }
        guard simulate || pushBlock(.blockQuote) else { return false }
        lexer.resultSymbol = Token.blockQuoteStart.rawValue
        return true
    }

    mutating func parseAtxHeading(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard valid[Token.atxH1Marker.rawValue] && indentation <= 3 else { return false }
        markEnd(&lexer)
        var level = 0
        while lexer.lookahead == 35 && level <= 6 {
            advance(&lexer)
            level += 1
        }
        if level <= 6
            && (lexer.lookahead == 32 || lexer.lookahead == 9
                || Self.isNewline(lexer.lookahead))
        {
            lexer.resultSymbol = Token.atxH1Marker.rawValue + level - 1
            indentation = 0
            markEnd(&lexer)
            return true
        }
        return false
    }

    mutating func parseSetextUnderline(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard valid[Token.setextH1Underline.rawValue] && matched == openBlocks.count else { return false }
        markEnd(&lexer)
        while lexer.lookahead == 61 { advance(&lexer) }
        while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
        if Self.isNewline(lexer.lookahead) {
            lexer.resultSymbol = Token.setextH1Underline.rawValue
            markEnd(&lexer)
            return true
        }
        return false
    }

    // Preserve metadata and list-marker precedence from the source scanner.
    // swiftlint:disable:next cyclomatic_complexity
    mutating func parsePlus(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard
            indentation <= 3
                && (valid[Token.listMarkerPlus.rawValue]
                    || valid[Token.listMarkerPlusDontInterrupt.rawValue] || valid[Token.plusMetadata.rawValue])
        else {
            return false
        }
        advance(&lexer)
        if valid[Token.plusMetadata.rawValue] && lexer.lookahead == 43 {
            advance(&lexer)
            guard lexer.lookahead == 43 else { return false }
            advance(&lexer)
            while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
            guard Self.isNewline(lexer.lookahead) else { return false }
            while true {
                advanceNewline(&lexer)
                var plusCount = 0
                while lexer.lookahead == 43 {
                    plusCount += 1
                    advance(&lexer)
                }
                if plusCount == 3 {
                    while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
                    if Self.isNewline(lexer.lookahead) {
                        advanceNewline(&lexer)
                        markEnd(&lexer)
                        lexer.resultSymbol = Token.plusMetadata.rawValue
                        return true
                    }
                }
                while !Self.isNewline(lexer.lookahead) && !lexer.isAtEnd { advance(&lexer) }
                if lexer.isAtEnd { break }
            }
        } else {
            var extraIndentation = 0
            while lexer.lookahead == 32 || lexer.lookahead == 9 {
                extraIndentation = (extraIndentation + advance(&lexer)) & 0xFF
            }
            var dontInterrupt = false
            if Self.isNewline(lexer.lookahead) {
                extraIndentation = 1
                dontInterrupt = true
            }
            dontInterrupt = dontInterrupt && matched == openBlocks.count
            let token: Token = dontInterrupt ? .listMarkerPlusDontInterrupt : .listMarkerPlus
            if extraIndentation >= 1 && valid[token.rawValue] {
                extraIndentation -= 1
                if extraIndentation <= 3 {
                    extraIndentation = (extraIndentation + indentation) & 0xFF
                    indentation = 0
                } else {
                    let temp = indentation
                    indentation = extraIndentation
                    extraIndentation = temp
                }
                guard let block = Block(rawValue: Block.listItem.rawValue + extraIndentation),
                    simulate || pushBlock(block)
                else { return false }
                lexer.resultSymbol = token.rawValue
                return true
            }
        }
        return false
    }

    mutating func parseOrderedListMarker(
        _ lexer: inout some ScannerLexer, validSymbols valid: [Bool]
    ) -> Bool {
        guard
            indentation <= 3
                && (valid[Token.listMarkerParenthesis.rawValue]
                    || valid[Token.listMarkerDot.rawValue]
                    || valid[Token.listMarkerParenthesisDontInterrupt.rawValue]
                    || valid[Token.listMarkerDotDontInterrupt.rawValue])
        else { return false }
        var digits = 1
        var dontInterrupt = false
        advance(&lexer)
        while (48 ... 57).contains(lexer.lookahead) {
            dontInterrupt = true
            digits += 1
            advance(&lexer)
        }
        guard digits <= 9 else { return false }
        let dot = lexer.lookahead == 46
        let parenthesis = lexer.lookahead == 41
        guard dot || parenthesis else { return false }
        advance(&lexer)
        var extraIndentation = 0
        while lexer.lookahead == 32 || lexer.lookahead == 9 {
            extraIndentation = (extraIndentation + advance(&lexer)) & 0xFF
        }
        if Self.isNewline(lexer.lookahead) {
            extraIndentation = 1
            dontInterrupt = true
        }
        dontInterrupt = dontInterrupt && matched == openBlocks.count
        let offered: Token =
            dot
            ? (dontInterrupt ? .listMarkerDotDontInterrupt : .listMarkerDot)
            : (dontInterrupt ? .listMarkerParenthesisDontInterrupt : .listMarkerParenthesis)
        guard extraIndentation >= 1 && valid[offered.rawValue] else { return false }
        extraIndentation -= 1
        if extraIndentation <= 3 {
            extraIndentation = (extraIndentation + indentation) & 0xFF
            indentation = 0
        } else {
            let temp = indentation
            indentation = extraIndentation
            extraIndentation = temp
        }
        guard let block = Block(rawValue: Block.listItem.rawValue + extraIndentation + digits),
            simulate || pushBlock(block)
        else { return false }
        // Upstream returns the base symbol even when the don't-interrupt symbol gated it.
        lexer.resultSymbol = (dot ? Token.listMarkerDot : .listMarkerParenthesis).rawValue
        return true
    }

    // Preserve setext, thematic-break, list, and metadata precedence.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func parseMinus(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard
            indentation <= 3
                && (valid[Token.listMarkerMinus.rawValue]
                    || valid[Token.listMarkerMinusDontInterrupt.rawValue]
                    || valid[Token.setextH2Underline.rawValue] || valid[Token.thematicBreak.rawValue]
                    || valid[Token.minusMetadata.rawValue])
        else { return false }
        markEnd(&lexer)
        var whitespaceAfterMinus = false
        var minusAfterWhitespace = false
        var minusCount = 0
        var extraIndentation = 0
        while true {
            if lexer.lookahead == 45 {
                if minusCount == 1 && extraIndentation >= 1 { markEnd(&lexer) }
                minusCount += 1
                advance(&lexer)
                minusAfterWhitespace = whitespaceAfterMinus
            } else if lexer.lookahead == 32 || lexer.lookahead == 9 {
                if minusCount == 1 {
                    extraIndentation = (extraIndentation + advance(&lexer)) & 0xFF
                } else {
                    advance(&lexer)
                }
                whitespaceAfterMinus = true
            } else {
                break
            }
        }
        let lineEnd = Self.isNewline(lexer.lookahead)
        var dontInterrupt = false
        if minusCount == 1 && lineEnd {
            extraIndentation = 1
            dontInterrupt = true
        }
        dontInterrupt = dontInterrupt && matched == openBlocks.count
        let thematicBreak = minusCount >= 3 && lineEnd
        let underline = minusCount >= 1 && !minusAfterWhitespace && lineEnd && matched == openBlocks.count
        let listMarkerMinus = minusCount >= 1 && extraIndentation >= 1
        var success = false
        if valid[Token.setextH2Underline.rawValue] && underline {
            lexer.resultSymbol = Token.setextH2Underline.rawValue
            markEnd(&lexer)
            indentation = 0
            success = true
        } else if valid[Token.thematicBreak.rawValue] && thematicBreak {
            lexer.resultSymbol = Token.thematicBreak.rawValue
            markEnd(&lexer)
            indentation = 0
            success = true
        } else {
            let token: Token = dontInterrupt ? .listMarkerMinusDontInterrupt : .listMarkerMinus
            if valid[token.rawValue] && listMarkerMinus {
                if minusCount == 1 { markEnd(&lexer) }
                extraIndentation -= 1
                if extraIndentation <= 3 {
                    extraIndentation = (extraIndentation + indentation) & 0xFF
                    indentation = 0
                } else {
                    let temp = indentation
                    indentation = extraIndentation
                    extraIndentation = temp
                }
                guard let block = Block(rawValue: Block.listItem.rawValue + extraIndentation),
                    simulate || pushBlock(block)
                else { return false }
                lexer.resultSymbol = token.rawValue
                return true
            }
        }
        if minusCount == 3 && !minusAfterWhitespace && lineEnd && valid[Token.minusMetadata.rawValue] {
            while true {
                advanceNewline(&lexer)
                minusCount = 0
                while lexer.lookahead == 45 {
                    minusCount += 1
                    advance(&lexer)
                }
                if minusCount == 3 {
                    while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
                    if Self.isNewline(lexer.lookahead) {
                        advanceNewline(&lexer)
                        markEnd(&lexer)
                        lexer.resultSymbol = Token.minusMetadata.rawValue
                        return true
                    }
                }
                while !Self.isNewline(lexer.lookahead) && !lexer.isAtEnd { advance(&lexer) }
                if lexer.isAtEnd { break }
            }
        }
        return success
    }

    mutating func advanceNewline(_ lexer: inout some ScannerLexer) {
        if lexer.lookahead == 13 {
            advance(&lexer)
            if lexer.lookahead == 10 { advance(&lexer) }
        } else {
            advance(&lexer)
        }
    }
}
