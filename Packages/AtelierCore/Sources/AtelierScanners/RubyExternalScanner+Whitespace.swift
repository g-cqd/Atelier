import AtelierParser

private func c(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

private enum RubyCharacter {
    static func isSpace(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.isWhitespace ?? false
    }

    static func isAlpha(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.isAlphabetic ?? false
    }

    static func isAlnum(_ value: UInt32) -> Bool {
        guard let properties = Unicode.Scalar(value)?.properties else { return false }
        return properties.isAlphabetic || properties.numericType != nil
    }

    static func isDigit(_ value: UInt32) -> Bool {
        Unicode.Scalar(value)?.properties.generalCategory == .decimalNumber
    }

    static func isIdentifier(_ value: UInt32) -> Bool {
        switch value {
            case 0, c("\n"), c("\r"), c("\t"), c(" "), c(":"), c(";"), c("`"), c("\""), c("'"),
                c("@"), c("$"), c("#"), c("."), c(","), c("|"), c("^"), c("&"), c("<"), c("="),
                c(">"), c("+"), c("-"), c("*"), c("/"), c("\\"), c("%"), c("?"), c("!"), c("~"),
                c("("), c(")"), c("["), c("]"), c("{"), c("}"):
                false
            default:
                true
        }
    }
}

extension RubyExternalScanner {
    mutating func scanWhitespace(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        let heredocBodyStartIsValid =
            !openHeredocs.isEmpty && !openHeredocs[0].started
            && validSymbols[TokenType.heredocBodyStart.rawValue]
        var crossedNewline = false

        while true {
            if !validSymbols[TokenType.noLineBreak.rawValue] && validSymbols[TokenType.lineBreak.rawValue]
                && lexer.isAtIncludedRangeStart
            {
                lexer.markEnd()
                lexer.resultSymbol = TokenType.lineBreak.rawValue
                return true
            }

            switch lexer.lookahead {
                case c(" "), c("\t"):
                    skip(&lexer)
                case c("\r"):
                    if heredocBodyStartIsValid {
                        lexer.resultSymbol = TokenType.heredocBodyStart.rawValue
                        openHeredocs[0].started = true
                        return true
                    }
                    skip(&lexer)
                case c("\n"):
                    if heredocBodyStartIsValid {
                        lexer.resultSymbol = TokenType.heredocBodyStart.rawValue
                        openHeredocs[0].started = true
                        return true
                    }
                    if !validSymbols[TokenType.noLineBreak.rawValue] && validSymbols[TokenType.lineBreak.rawValue]
                        && !crossedNewline
                    {
                        lexer.markEnd()
                        lexer.advance(skip: false)
                        crossedNewline = true
                    } else {
                        skip(&lexer)
                    }
                case c("\\"):
                    lexer.advance(skip: false)
                    if lexer.lookahead == c("\r") { skip(&lexer) }
                    guard RubyCharacter.isSpace(lexer.lookahead) else {
                        return false
                    }
                    skip(&lexer)
                default:
                    if crossedNewline {
                        if lexer.lookahead != c(".") && lexer.lookahead != c("&")
                            && lexer.lookahead != c("#")
                        {
                            lexer.resultSymbol = TokenType.lineBreak.rawValue
                        } else if lexer.lookahead == c(".") {
                            // Don't return LINE_BREAK for the call operator (`.`) but do return one for range
                            // operators (`..` and `...`)
                            lexer.advance(skip: false)
                            guard !lexer.isAtEnd && lexer.lookahead == c(".") else {
                                return false
                            }
                            lexer.resultSymbol = TokenType.lineBreak.rawValue
                        }
                    }
                    return true
            }
        }
    }

    private mutating func skip(_ lexer: inout some ScannerLexer) {
        hasLeadingWhitespace = true
        lexer.advance(skip: true)
    }

    private static func scanOperator(_ lexer: inout some ScannerLexer) -> Bool {
        switch lexer.lookahead {
            // <, <=, <<, <=>
            case c("<"):
                lexer.advance(skip: false)
                if lexer.lookahead == c("<") {
                    lexer.advance(skip: false)
                } else if lexer.lookahead == c("=") {
                    lexer.advance(skip: false)
                    if lexer.lookahead == c(">") { lexer.advance(skip: false) }
                }
                return true

            // >, >=, >>
            case c(">"):
                lexer.advance(skip: false)
                if lexer.lookahead == c(">") || lexer.lookahead == c("=") { lexer.advance(skip: false) }
                return true

            // ==, ===, =~
            case c("="):
                lexer.advance(skip: false)
                if lexer.lookahead == c("~") {
                    lexer.advance(skip: false)
                    return true
                }
                if lexer.lookahead == c("=") {
                    lexer.advance(skip: false)
                    if lexer.lookahead == c("=") { lexer.advance(skip: false) }
                    return true
                }
                return false

            // +, -, ~, +@, -@, ~@
            case c("+"), c("-"), c("~"):
                lexer.advance(skip: false)
                if lexer.lookahead == c("@") { lexer.advance(skip: false) }
                return true

            // ..
            case c("."):
                lexer.advance(skip: false)
                if lexer.lookahead == c(".") {
                    lexer.advance(skip: false)
                    return true
                }
                return false

            // &, ^, |, /, %`, !, !=, !~, *, **
            case c("&"), c("^"), c("|"), c("/"), c("%"), c("`"):
                lexer.advance(skip: false)
                return true
            case c("!"):
                lexer.advance(skip: false)
                if lexer.lookahead == c("=") || lexer.lookahead == c("~") { lexer.advance(skip: false) }
                return true
            case c("*"):
                lexer.advance(skip: false)
                if lexer.lookahead == c("*") { lexer.advance(skip: false) }
                return true

            // [], []=
            case c("["):
                lexer.advance(skip: false)
                guard lexer.lookahead == c("]") else { return false }
                lexer.advance(skip: false)
                if lexer.lookahead == c("=") { lexer.advance(skip: false) }
                return true
            default:
                return false
        }
    }

    static func scanSymbolIdentifier(_ lexer: inout some ScannerLexer) -> Bool {
        if lexer.lookahead == c("@") {
            lexer.advance(skip: false)
            if lexer.lookahead == c("@") { lexer.advance(skip: false) }
        } else if lexer.lookahead == c("$") {
            lexer.advance(skip: false)
        }

        if RubyCharacter.isIdentifier(lexer.lookahead) {
            lexer.advance(skip: false)
        } else if !scanOperator(&lexer) {
            return false
        }
        while RubyCharacter.isIdentifier(lexer.lookahead) { lexer.advance(skip: false) }
        if lexer.lookahead == c("?") || lexer.lookahead == c("!") { lexer.advance(skip: false) }
        if lexer.lookahead == c("=") {
            lexer.markEnd()
            lexer.advance(skip: false)
            if lexer.lookahead != c(">") { lexer.markEnd() }
        }
        return true
    }

    static func scanShortInterpolation(
        _ lexer: inout some ScannerLexer, hasContent: Bool, contentSymbol: TokenType
    ) -> Bool {
        let start = lexer.lookahead
        guard start == c("@") || start == c("$") else { return false }
        if hasContent {
            lexer.resultSymbol = contentSymbol.rawValue
            return true
        }
        lexer.markEnd()
        lexer.advance(skip: false)
        var isShortInterpolation = false
        if start == c("$") {
            switch lexer.lookahead {
                case c("!"), c("@"), c("&"), c("`"), c("'"), c("+"), c("~"), c("="), c("/"),
                    c("\\"), c(","), c(";"), c("."), c("<"), c(">"), c("*"), c("?"), c(":"), c("\""):
                    isShortInterpolation = true
                case c("-"):
                    lexer.advance(skip: false)
                    isShortInterpolation = RubyCharacter.isAlpha(lexer.lookahead) || lexer.lookahead == c("_")
                default:
                    isShortInterpolation = RubyCharacter.isAlnum(lexer.lookahead) || lexer.lookahead == c("_")
            }
        }
        if start == c("@") {
            if lexer.lookahead == c("@") { lexer.advance(skip: false) }
            isShortInterpolation =
                RubyCharacter.isIdentifier(lexer.lookahead)
                && !RubyCharacter.isDigit(lexer.lookahead)
        }
        if isShortInterpolation {
            lexer.resultSymbol = TokenType.shortInterpolation.rawValue
            return true
        }
        return false
    }
}
