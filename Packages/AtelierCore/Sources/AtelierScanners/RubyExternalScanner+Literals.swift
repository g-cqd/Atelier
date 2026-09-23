import AtelierParser

private func c(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

private func isSpace(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isWhitespace ?? false
}

private func isLower(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isLowercase ?? false
}

extension RubyExternalScanner {
    func scanOpenDelimiter(
        _ lexer: inout some ScannerLexer, literal: inout Literal, validSymbols: [Bool]
    ) -> Bool {
        switch lexer.lookahead {
            case c("\""):
                literal.type = .stringStart
                literal.openDelimiter = lexer.lookahead
                literal.closeDelimiter = lexer.lookahead
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
                return true

            case c("'"):
                literal.type = .stringStart
                literal.openDelimiter = lexer.lookahead
                literal.closeDelimiter = lexer.lookahead
                literal.allowsInterpolation = false
                lexer.advance(skip: false)
                return true

            case c("`"):
                guard validSymbols[TokenType.subshellStart.rawValue] else { return false }
                literal.type = .subshellStart
                literal.openDelimiter = lexer.lookahead
                literal.closeDelimiter = lexer.lookahead
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
                return true

            case c("/"):
                guard validSymbols[TokenType.regexStart.rawValue] else { return false }
                literal.type = .regexStart
                literal.openDelimiter = lexer.lookahead
                literal.closeDelimiter = lexer.lookahead
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
                if validSymbols[TokenType.forwardSlash.rawValue] {
                    if !hasLeadingWhitespace { return false }
                    if lexer.lookahead == c(" ") || lexer.lookahead == c("\t") || lexer.lookahead == c("\n")
                        || lexer.lookahead == c("\r") || lexer.lookahead == c("=")
                    {
                        return false
                    }
                }
                return true

            case c("%"):
                return scanPercentDelimiter(&lexer, literal: &literal, validSymbols: validSymbols)

            default:
                return false
        }
    }

    private func scanPercentDelimiter(
        _ lexer: inout some ScannerLexer, literal: inout Literal, validSymbols: [Bool]
    ) -> Bool {
        lexer.advance(skip: false)
        guard scanPercentType(&lexer, literal: &literal, validSymbols: validSymbols),
            scanPercentClosingDelimiter(&lexer, literal: &literal, validSymbols: validSymbols)
        else { return false }
        lexer.advance(skip: false)
        return true
    }

    private func scanPercentType(
        _ lexer: inout some ScannerLexer, literal: inout Literal, validSymbols: [Bool]
    ) -> Bool {
        switch lexer.lookahead {
            case c("s"):
                guard validSymbols[TokenType.simpleSymbol.rawValue] else { return false }
                literal.type = .symbolStart
                literal.allowsInterpolation = false
                lexer.advance(skip: false)
            case c("r"):
                guard validSymbols[TokenType.regexStart.rawValue] else { return false }
                literal.type = .regexStart
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
            case c("x"):
                guard validSymbols[TokenType.subshellStart.rawValue] else { return false }
                literal.type = .subshellStart
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
            case c("q"):
                guard validSymbols[TokenType.stringStart.rawValue] else { return false }
                literal.type = .stringStart
                literal.allowsInterpolation = false
                lexer.advance(skip: false)
            case c("Q"):
                guard validSymbols[TokenType.stringStart.rawValue] else { return false }
                literal.type = .stringStart
                literal.allowsInterpolation = true
                lexer.advance(skip: false)
            case c("w"), c("W"):
                guard validSymbols[TokenType.stringArrayStart.rawValue] else { return false }
                literal.type = .stringArrayStart
                literal.allowsInterpolation = lexer.lookahead == c("W")
                lexer.advance(skip: false)
            case c("i"), c("I"):
                guard validSymbols[TokenType.symbolArrayStart.rawValue] else { return false }
                literal.type = .symbolArrayStart
                literal.allowsInterpolation = lexer.lookahead == c("I")
                lexer.advance(skip: false)
            default:
                guard validSymbols[TokenType.stringStart.rawValue] else { return false }
                literal.type = .stringStart
                literal.allowsInterpolation = true
        }
        return true
    }

    private func scanPercentClosingDelimiter(
        _ lexer: inout some ScannerLexer, literal: inout Literal, validSymbols: [Bool]
    ) -> Bool {
        switch lexer.lookahead {
            case c("("):
                literal.openDelimiter = c("(")
                literal.closeDelimiter = c(")")
            case c("["):
                literal.openDelimiter = c("[")
                literal.closeDelimiter = c("]")
            case c("{"):
                literal.openDelimiter = c("{")
                literal.closeDelimiter = c("}")
            case c("<"):
                literal.openDelimiter = c("<")
                literal.closeDelimiter = c(">")
            case c("\r"), c("\n"), c(" "), c("\t"):
                // If the `/` operator is valid, then so is the `%` operator, which means
                // that a `%` followed by whitespace should be considered an operator,
                // not a percent string.
                if validSymbols[TokenType.forwardSlash.rawValue] { return false }
            case c("|"), c("!"), c("#"), c("/"), c("\\"), c("@"), c("$"), c("%"), c("^"),
                c("&"), c("*"), c(")"), c("]"), c("}"), c(">"), c("+"), c("-"), c("~"),
                c("`"), c(","), c("."), c("?"), c(":"), c(";"), c("_"), c("\""), c("'"):
                // '=' remains excluded because it conflicts with the %= assignment operator.
                literal.openDelimiter = lexer.lookahead
                literal.closeDelimiter = lexer.lookahead
            default:
                return false
        }
        return true
    }

    mutating func scanLiteralContent(_ lexer: inout some ScannerLexer) -> Bool {
        guard let last = literalStack.indices.last else { return false }
        var literal = literalStack[last]
        var hasContent = false
        let stopOnSpace = literal.type == .symbolArrayStart || literal.type == .stringArrayStart

        while true {
            if stopOnSpace && isSpace(lexer.lookahead) {
                if hasContent {
                    lexer.markEnd()
                    lexer.resultSymbol = TokenType.stringContent.rawValue
                    literalStack[last] = literal
                    return true
                }
                literalStack[last] = literal
                return false
            }
            if lexer.lookahead == literal.closeDelimiter {
                lexer.markEnd()
                if literal.nestingDepth == 1 {
                    if hasContent {
                        lexer.resultSymbol = TokenType.stringContent.rawValue
                    } else {
                        lexer.advance(skip: false)
                        if literal.type == .regexStart {
                            while isLower(lexer.lookahead) { lexer.advance(skip: false) }
                        }
                        literalStack.removeLast()
                        lexer.resultSymbol = TokenType.stringEnd.rawValue
                        lexer.markEnd()
                    }
                    return true
                }
                literal.nestingDepth -= 1
                lexer.advance(skip: false)
            } else if lexer.lookahead == literal.openDelimiter {
                literal.nestingDepth += 1
                lexer.advance(skip: false)
            } else if literal.allowsInterpolation && lexer.lookahead == c("#") {
                if let result = Self.scanLiteralInterpolation(&lexer, hasContent: hasContent) {
                    literalStack[last] = literal
                    return result
                }
            } else if lexer.lookahead == c("\\") {
                if let result = Self.scanLiteralEscape(
                    &lexer, allowsInterpolation: literal.allowsInterpolation, hasContent: hasContent
                ) {
                    literalStack[last] = literal
                    return result
                }
            } else if lexer.isAtEnd {
                lexer.advance(skip: false)
                lexer.markEnd()
                literalStack[last] = literal
                return false
            } else {
                lexer.advance(skip: false)
            }
            hasContent = true
        }
    }

    private static func scanLiteralInterpolation(
        _ lexer: inout some ScannerLexer, hasContent: Bool
    ) -> Bool? {
        lexer.markEnd()
        lexer.advance(skip: false)
        if lexer.lookahead == c("{") {
            if hasContent { lexer.resultSymbol = TokenType.stringContent.rawValue }
            return hasContent
        }
        if scanShortInterpolation(&lexer, hasContent: hasContent, contentSymbol: .stringContent) {
            return true
        }
        return nil
    }

    private static func scanLiteralEscape(
        _ lexer: inout some ScannerLexer, allowsInterpolation: Bool, hasContent: Bool
    ) -> Bool? {
        if allowsInterpolation {
            if hasContent {
                lexer.markEnd()
                lexer.resultSymbol = TokenType.stringContent.rawValue
            }
            return hasContent
        }
        lexer.advance(skip: false)
        lexer.advance(skip: false)
        return nil
    }
}
