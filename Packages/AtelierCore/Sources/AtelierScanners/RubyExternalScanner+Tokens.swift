import AtelierParser

private func c(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

private func isSpace(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isWhitespace ?? false
}

private func isAlpha(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isAlphabetic ?? false
}

private func isAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

private func isUpper(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isUppercase ?? false
}

private func isDigit(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.generalCategory == .decimalNumber
}

extension RubyExternalScanner {
    mutating func scanToken(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        switch lexer.lookahead {
            case c("&"):
                if validSymbols[TokenType.blockAmpersand.rawValue] {
                    return scanBlockAmpersand(&lexer)
                }
            case c("<"):
                if validSymbols[TokenType.singletonClassLeftAngleLeftAngle.rawValue] {
                    return scanSingletonClass(&lexer)
                }
            case c("*"):
                if validSymbols[TokenType.splatStar.rawValue] || validSymbols[TokenType.binaryStar.rawValue]
                    || validSymbols[TokenType.hashSplatStarStar.rawValue]
                    || validSymbols[TokenType.binaryStarStar.rawValue]
                {
                    return scanStar(&lexer, validSymbols: validSymbols)
                }
            case c("-"):
                if validSymbols[TokenType.unaryMinus.rawValue] || validSymbols[TokenType.unaryMinusNum.rawValue]
                    || validSymbols[TokenType.binaryMinus.rawValue]
                {
                    return scanMinus(&lexer, validSymbols: validSymbols)
                }
            case c(":"):
                if validSymbols[TokenType.symbolStart.rawValue] {
                    return scanSymbol(&lexer)
                }
            case c("["):
                // Treat a square bracket as an element reference if either:
                // * the bracket is not preceded by any whitespace
                // * an arbitrary expression is not valid at the current position.
                if validSymbols[TokenType.elementReferenceBracket.rawValue]
                    && (!hasLeadingWhitespace || !validSymbols[TokenType.stringStart.rawValue])
                {
                    lexer.advance(skip: false)
                    lexer.resultSymbol = TokenType.elementReferenceBracket.rawValue
                    return true
                }

            default:
                break
        }

        // Open delimiters for literals
        if shouldScanIdentifier(lexer.lookahead, validSymbols: validSymbols) {
            return scanIdentifier(&lexer, validSymbols: validSymbols)
        }

        // Open delimiters for literals
        if validSymbols[TokenType.stringStart.rawValue] {
            return scanLiteralStart(&lexer, validSymbols: validSymbols)
        }
        return false
    }

    private func scanBlockAmpersand(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.advance(skip: false)
        guard
            lexer.lookahead != c("&") && lexer.lookahead != c(".") && lexer.lookahead != c("=")
                && !isSpace(lexer.lookahead)
        else { return false }
        lexer.resultSymbol = TokenType.blockAmpersand.rawValue
        return true
    }

    private func scanSingletonClass(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.advance(skip: false)
        guard lexer.lookahead == c("<") else { return false }
        lexer.advance(skip: false)
        lexer.resultSymbol = TokenType.singletonClassLeftAngleLeftAngle.rawValue
        return true
    }

    private func scanMinus(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        lexer.advance(skip: false)
        guard lexer.lookahead != c("=") && lexer.lookahead != c(">") else { return false }
        if validSymbols[TokenType.unaryMinusNum.rawValue]
            && (!validSymbols[TokenType.binaryStar.rawValue] || hasLeadingWhitespace)
            && isDigit(lexer.lookahead)
        {
            lexer.resultSymbol = TokenType.unaryMinusNum.rawValue
            return true
        }
        if validSymbols[TokenType.unaryMinus.rawValue] && hasLeadingWhitespace && !isSpace(lexer.lookahead) {
            lexer.resultSymbol = TokenType.unaryMinus.rawValue
        } else if validSymbols[TokenType.binaryMinus.rawValue] {
            lexer.resultSymbol = TokenType.binaryMinus.rawValue
        } else {
            lexer.resultSymbol = TokenType.unaryMinus.rawValue
        }
        return true
    }

    private mutating func scanSymbol(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.advance(skip: false)
        if lexer.lookahead == c("\"") || lexer.lookahead == c("'") {
            let quote = lexer.lookahead
            lexer.advance(skip: false)
            guard canAddLiteral() else { return false }
            literalStack.append(
                Literal(
                    type: .symbolStart, openDelimiter: quote, closeDelimiter: quote,
                    nestingDepth: 1, allowsInterpolation: quote == c("\"")
                ))
            lexer.resultSymbol = TokenType.symbolStart.rawValue
            return true
        }
        guard Self.scanSymbolIdentifier(&lexer) else { return false }
        lexer.resultSymbol = TokenType.simpleSymbol.rawValue
        return true
    }

    private func shouldScanIdentifier(_ value: UInt32, validSymbols: [Bool]) -> Bool {
        ((validSymbols[TokenType.hashKeySymbol.rawValue] || validSymbols[TokenType.identifierSuffix.rawValue])
            && (isAlpha(value) || value == c("_")))
            || (validSymbols[TokenType.constantSuffix.rawValue] && isUpper(value))
    }

    private func scanIdentifier(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        let validIdentifierSymbol: TokenType = isUpper(lexer.lookahead) ? .constantSuffix : .identifierSuffix
        while isAlnum(lexer.lookahead) || lexer.lookahead == c("_") { lexer.advance(skip: false) }
        if validSymbols[TokenType.hashKeySymbol.rawValue] && lexer.lookahead == c(":") {
            lexer.markEnd()
            lexer.advance(skip: false)
            if lexer.lookahead != c(":") {
                lexer.resultSymbol = TokenType.hashKeySymbol.rawValue
                return true
            }
        } else if validSymbols[validIdentifierSymbol.rawValue] && lexer.lookahead == c("!") {
            lexer.advance(skip: false)
            if lexer.lookahead != c("=") {
                lexer.resultSymbol = validIdentifierSymbol.rawValue
                return true
            }
        }
        return false
    }

    private mutating func scanLiteralStart(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        if lexer.lookahead == c("<") {
            lexer.advance(skip: false)
            guard lexer.lookahead == c("<") else { return false }
            lexer.advance(skip: false)
            var heredoc = Heredoc()
            if lexer.lookahead == c("-") || lexer.lookahead == c("~") {
                lexer.advance(skip: false)
                heredoc.endWordIndentationAllowed = true
            }
            guard Self.scanHeredocWord(&lexer, heredoc: &heredoc), !heredoc.word.isEmpty,
                canAddHeredoc(heredoc)
            else { return false }
            openHeredocs.append(heredoc)
            lexer.resultSymbol = TokenType.heredocStart.rawValue
            return true
        }
        var literal = Literal(nestingDepth: 1)
        guard scanOpenDelimiter(&lexer, literal: &literal, validSymbols: validSymbols), canAddLiteral() else {
            return false
        }
        literalStack.append(literal)
        lexer.resultSymbol = literal.type.rawValue
        return true
    }

    private var serializedStateSize: Int {
        2 + literalStack.count * 5 + openHeredocs.reduce(0) { $0 + 4 + $1.word.count }
    }

    private func canAddLiteral() -> Bool {
        literalStack.count < UInt8.max && serializedStateSize + 5 < maximumSerializedScannerStateSize
    }

    private func canAddHeredoc(_ heredoc: Heredoc) -> Bool {
        openHeredocs.count < UInt8.max
            && serializedStateSize + 4 + heredoc.word.count <= maximumSerializedScannerStateSize
    }

    private func scanStar(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        lexer.advance(skip: false)
        if lexer.lookahead == c("=") { return false }
        if lexer.lookahead == c("*") {
            if validSymbols[TokenType.hashSplatStarStar.rawValue] || validSymbols[TokenType.binaryStarStar.rawValue] {
                lexer.advance(skip: false)
                if lexer.lookahead == c("=") { return false }
                if validSymbols[TokenType.binaryStarStar.rawValue] && !hasLeadingWhitespace {
                    lexer.resultSymbol = TokenType.binaryStarStar.rawValue
                    return true
                }
                if validSymbols[TokenType.hashSplatStarStar.rawValue] && !isSpace(lexer.lookahead) {
                    lexer.resultSymbol = TokenType.hashSplatStarStar.rawValue
                    return true
                }
                if validSymbols[TokenType.binaryStarStar.rawValue] {
                    lexer.resultSymbol = TokenType.binaryStarStar.rawValue
                    return true
                }
                if validSymbols[TokenType.hashSplatStarStar.rawValue] {
                    lexer.resultSymbol = TokenType.hashSplatStarStar.rawValue
                    return true
                }
                return false
            }
            return false
        }
        if validSymbols[TokenType.binaryStar.rawValue] && !hasLeadingWhitespace {
            lexer.resultSymbol = TokenType.binaryStar.rawValue
            return true
        }
        if validSymbols[TokenType.splatStar.rawValue] && !isSpace(lexer.lookahead) {
            lexer.resultSymbol = TokenType.splatStar.rawValue
            return true
        }
        if validSymbols[TokenType.binaryStar.rawValue] {
            lexer.resultSymbol = TokenType.binaryStar.rawValue
            return true
        }
        if validSymbols[TokenType.splatStar.rawValue] {
            lexer.resultSymbol = TokenType.splatStar.rawValue
            return true
        }
        return false
    }
}
