import AtelierParser

private func c(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

private func isAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

extension RubyExternalScanner {
    static func scanHeredocWord(_ lexer: inout some ScannerLexer, heredoc: inout Heredoc) -> Bool {
        var word: [UInt8] = []
        var quote: UInt32 = 0
        switch lexer.lookahead {
            case c("'"), c("\""), c("`"):
                quote = lexer.lookahead
                lexer.advance(skip: false)
                while lexer.lookahead != quote && !lexer.isAtEnd {
                    guard word.count < UInt8.max else { return false }
                    word.append(UInt8(truncatingIfNeeded: lexer.lookahead))
                    lexer.advance(skip: false)
                }
                lexer.advance(skip: false)
            default:
                if isAlnum(lexer.lookahead) || lexer.lookahead == c("_") {
                    guard word.count < UInt8.max else { return false }
                    word.append(UInt8(truncatingIfNeeded: lexer.lookahead))
                    lexer.advance(skip: false)
                    while isAlnum(lexer.lookahead) || lexer.lookahead == c("_") {
                        guard word.count < UInt8.max else { return false }
                        word.append(UInt8(truncatingIfNeeded: lexer.lookahead))
                        lexer.advance(skip: false)
                    }
                }
        }
        heredoc.word = word
        heredoc.allowsInterpolation = quote != c("'")
        return true
    }

    mutating func scanHeredocContent(_ lexer: inout some ScannerLexer) -> Bool {
        guard let heredoc = openHeredocs.first, !heredoc.word.isEmpty else { return false }
        var positionInWord = 0
        var lookForHeredocEnd = true
        var hasContent = false

        while true {
            if positionInWord == heredoc.word.count {
                if !hasContent { lexer.markEnd() }
                while lexer.lookahead == c(" ") || lexer.lookahead == c("\t") {
                    lexer.advance(skip: false)
                }
                if lexer.lookahead == c("\n") || lexer.lookahead == c("\r") {
                    if hasContent {
                        lexer.resultSymbol = TokenType.heredocContent.rawValue
                    } else {
                        openHeredocs.removeFirst()
                        lexer.resultSymbol = TokenType.heredocBodyEnd.rawValue
                    }
                    return true
                }
                hasContent = true
                positionInWord = 0
            }

            if lexer.isAtEnd {
                lexer.markEnd()
                if hasContent {
                    lexer.resultSymbol = TokenType.heredocContent.rawValue
                } else {
                    openHeredocs.removeFirst()
                    lexer.resultSymbol = TokenType.heredocBodyEnd.rawValue
                }
                return true
            }

            if lexer.lookahead == UInt32(heredoc.word[positionInWord]) && lookForHeredocEnd {
                lexer.advance(skip: false)
                positionInWord += 1
            } else {
                positionInWord = 0
                lookForHeredocEnd = false
                if heredoc.allowsInterpolation && lexer.lookahead == c("\\") {
                    if hasContent {
                        lexer.resultSymbol = TokenType.heredocContent.rawValue
                        return true
                    }
                    return false
                }

                if heredoc.allowsInterpolation && lexer.lookahead == c("#") {
                    if let result = Self.scanHeredocInterpolation(&lexer, hasContent: hasContent) {
                        return result
                    }
                } else if lexer.lookahead == c("\r") || lexer.lookahead == c("\n") {
                    hasContent = true
                    lookForHeredocEnd = Self.scanHeredocNewline(
                        &lexer, indentationAllowed: heredoc.endWordIndentationAllowed
                    )
                } else {
                    hasContent = true
                    lexer.advance(skip: false)
                    lexer.markEnd()
                }
            }
        }
    }

    private static func scanHeredocInterpolation(
        _ lexer: inout some ScannerLexer, hasContent: Bool
    ) -> Bool? {
        lexer.markEnd()
        lexer.advance(skip: false)
        if lexer.lookahead == c("{") {
            if hasContent { lexer.resultSymbol = TokenType.heredocContent.rawValue }
            return hasContent
        }
        if scanShortInterpolation(&lexer, hasContent: hasContent, contentSymbol: .heredocContent) {
            return true
        }
        return nil
    }

    private static func scanHeredocNewline(
        _ lexer: inout some ScannerLexer, indentationAllowed: Bool
    ) -> Bool {
        if lexer.lookahead == c("\r") {
            lexer.advance(skip: false)
            if lexer.lookahead == c("\n") { lexer.advance(skip: false) }
        } else {
            lexer.advance(skip: false)
        }
        var lookForHeredocEnd = true
        while lexer.lookahead == c(" ") || lexer.lookahead == c("\t") {
            lexer.advance(skip: false)
            if !indentationAllowed { lookForHeredocEnd = false }
        }
        lexer.markEnd()
        return lookForHeredocEnd
    }
}
