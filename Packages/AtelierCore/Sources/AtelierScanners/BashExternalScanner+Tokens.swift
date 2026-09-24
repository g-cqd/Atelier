import AtelierParser

private func isSpace(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isWhitespace ?? false }

private func isAlpha(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isAlphabetic ?? false }

private func isDigit(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.generalCategory == .decimalNumber }

extension BashExternalScanner {
    // Mirrors the upstream C function branch for branch, so the port stays comparable with it line by line.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanUnchecked(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        if valid[.concat] && !valid[.errorRecovery] {
            if !(lexer.lookahead == 0 || isSpace(lexer.lookahead)
                || [0x3E, 0x3C, 0x29, 0x28, 0x3B, 0x26, 0x7C].contains(lexer.lookahead)
                || (lexer.lookahead == 0x7D && valid[.closingBrace])
                || (lexer.lookahead == 0x5D && valid[.closingBracket]))
            {
                Self.emit(.concat, &lexer)
                // So for a`b`, return concat if the second backtick has whitespace after it.
                if lexer.lookahead == 0x60 {
                    lexer.markEnd()
                    Self.advance(&lexer)
                    while lexer.lookahead != 0x60 && !lexer.isAtEnd { Self.advance(&lexer) }
                    if lexer.isAtEnd { return false }
                    if lexer.lookahead == 0x60 { Self.advance(&lexer) }
                    return isSpace(lexer.lookahead) || lexer.isAtEnd
                }
                // Strings with expansions that contain escaped quotes or
                // backslashes need this to return a concat.
                guard lexer.lookahead == 0x5C else {
                    return true
                }
                lexer.markEnd()
                Self.advance(&lexer)
                if [0x22, 0x27, 0x5C].contains(lexer.lookahead) { return true }
                if lexer.isAtEnd { return false }
            }
            if isSpace(lexer.lookahead) && valid[.closingBrace] && !valid[.expansionWord] {
                Self.emit(.concat, &lexer)
                return true
            }
        }

        if valid[.immediateDoubleHash] && !valid[.errorRecovery] {
            // Advance two # and ensure not } after.
            if lexer.lookahead == 0x23 {
                lexer.markEnd()
                Self.advance(&lexer)
                if lexer.lookahead == 0x23 {
                    Self.advance(&lexer)
                    if lexer.lookahead != 0x7D {
                        Self.emit(.immediateDoubleHash, &lexer)
                        lexer.markEnd()
                        return true
                    }
                }
            }
        }

        if valid[.expansionSymHash] && !valid[.errorRecovery] {
            if [0x23, 0x3D, 0x21].contains(lexer.lookahead) {
                let symbol: TokenType =
                    lexer.lookahead == 0x23
                    ? .expansionSymHash
                    : lexer.lookahead == 0x21 ? .expansionSymBang : .expansionSymEqual
                Self.emit(symbol, &lexer)
                Self.advance(&lexer)
                lexer.markEnd()
                while [0x23, 0x3D, 0x21].contains(lexer.lookahead) { Self.advance(&lexer) }
                while isSpace(lexer.lookahead) { Self.skip(&lexer) }
                return lexer.lookahead == 0x7D
            }
        }

        if valid[.emptyValue] {
            if isSpace(lexer.lookahead) || lexer.isAtEnd || lexer.lookahead == 0x3B
                || lexer.lookahead == 0x26
            {
                Self.emit(.emptyValue, &lexer)
                return true
            }
        }

        if (valid[.heredocBodyBeginning] || valid[.simpleHeredocBody]) && !heredocs.isEmpty
            && !heredocs[heredocs.count - 1].started && !valid[.errorRecovery]
        {
            return scanHeredocContent(&lexer, middleType: .heredocBodyBeginning, endType: .simpleHeredocBody)
        }

        if valid[.heredocEnd] && !heredocs.isEmpty {
            if scanHeredocEndIdentifier(&lexer) {
                heredocs.removeLast()
                Self.emit(.heredocEnd, &lexer)
                return true
            }
        }

        if valid[.heredocContent] && !heredocs.isEmpty && heredocs[heredocs.count - 1].started
            && !valid[.errorRecovery]
        {
            return scanHeredocContent(&lexer, middleType: .heredocContent, endType: .heredocEnd)
        }

        if valid[.heredocStart] && !valid[.errorRecovery] && !heredocs.isEmpty {
            return scanHeredocStart(&lexer)
        }

        if valid[.testOperator] && !valid[.expansionWord] {
            while isSpace(lexer.lookahead) && lexer.lookahead != 0x0A { Self.skip(&lexer) }
            if lexer.lookahead == 0x5C {
                if valid[.extglobPattern] { return scanExtglobPattern(&lexer, validSymbols: valid) }
                if valid[.regexNoSpace] { return scanRegex(&lexer, validSymbols: valid) }
                Self.skip(&lexer)
                if lexer.isAtEnd { return false }
                if lexer.lookahead == 0x0D {
                    Self.skip(&lexer)
                    if lexer.lookahead == 0x0A { Self.skip(&lexer) }
                } else if lexer.lookahead == 0x0A {
                    Self.skip(&lexer)
                } else {
                    return false
                }
                while isSpace(lexer.lookahead) { Self.skip(&lexer) }
            }
            if lexer.lookahead == 0x0A && !valid[.newline] {
                Self.skip(&lexer)
                while isSpace(lexer.lookahead) { Self.skip(&lexer) }
            }
            if lexer.lookahead == 0x2D {
                Self.advance(&lexer)
                var advancedOnce = false
                while isAlpha(lexer.lookahead) {
                    advancedOnce = true
                    Self.advance(&lexer)
                }
                if isSpace(lexer.lookahead) && advancedOnce {
                    lexer.markEnd()
                    Self.advance(&lexer)
                    if lexer.lookahead == 0x7D && valid[.closingBrace] {
                        if valid[.expansionWord] {
                            lexer.markEnd()
                            Self.emit(.expansionWord, &lexer)
                            return true
                        }
                        return false
                    }
                    Self.emit(.testOperator, &lexer)
                    return true
                }
                if isSpace(lexer.lookahead) && valid[.extglobPattern] {
                    Self.emit(.extglobPattern, &lexer)
                    return true
                }
            }
            if valid[.bareDollar] && !valid[.errorRecovery] && Self.scanBareDollar(&lexer) { return true }
        }

        if (valid[.variableName] || valid[.fileDescriptor] || valid[.heredocArrow])
            && !valid[.regexNoSlash] && !valid[.errorRecovery]
        {
            return scanVariableOrArrow(&lexer, validSymbols: valid)
        }

        if valid[.bareDollar] && !valid[.errorRecovery] && Self.scanBareDollar(&lexer) { return true }
        if valid[.regex] || valid[.regexNoSlash] || valid[.regexNoSpace] {
            return scanRegex(&lexer, validSymbols: valid)
        }
        if valid[.extglobPattern] { return scanExtglobPattern(&lexer, validSymbols: valid) }
        if valid[.expansionWord] { return scanExpansionWord(&lexer) }
        if valid[.braceStart] { return scanBraceStart(&lexer, validSymbols: valid) }
        return false
    }

    // Mirrors the upstream C function branch for branch, so the port stays comparable with it line by line.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanVariableOrArrow(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        while true {
            if ([0x20, 0x09, 0x0D].contains(lexer.lookahead)
                || (lexer.lookahead == 0x0A && !valid[.newline])) && !valid[.expansionWord]
            {
                Self.skip(&lexer)
            } else if lexer.lookahead == 0x5C {
                Self.skip(&lexer)
                if lexer.isAtEnd {
                    lexer.markEnd()
                    Self.emit(.variableName, &lexer)
                    return true
                }
                if lexer.lookahead == 0x0D { Self.skip(&lexer) }
                guard lexer.lookahead == 0x0A else {
                    if lexer.lookahead == 0x5C && valid[.expansionWord] {
                        return scanExpansionWord(&lexer)
                    }
                    return false
                }
                Self.skip(&lexer)
            } else {
                break
            }
        }

        // No '*', '@', '?', '-', '$', '0', '_'.
        if !valid[.expansionWord] && [0x2A, 0x40, 0x3F, 0x2D, 0x30, 0x5F].contains(lexer.lookahead) {
            lexer.markEnd()
            Self.advance(&lexer)
            if [0x3D, 0x5B, 0x3A, 0x2D, 0x25, 0x23, 0x2F].contains(lexer.lookahead) { return false }
            if valid[.extglobPattern] && isSpace(lexer.lookahead) {
                lexer.markEnd()
                Self.emit(.extglobPattern, &lexer)
                return true
            }
        }

        if valid[.heredocArrow] && lexer.lookahead == 0x3C {
            Self.advance(&lexer)
            if lexer.lookahead == 0x3C {
                Self.advance(&lexer)
                if lexer.lookahead == 0x2D {
                    Self.advance(&lexer)
                    heredocs.append(Heredoc(allowsIndent: true))
                    Self.emit(.heredocArrowDash, &lexer)
                } else if lexer.lookahead == 0x3C || lexer.lookahead == 0x3D {
                    return false
                } else {
                    heredocs.append(Heredoc())
                    Self.emit(.heredocArrow, &lexer)
                }
                return true
            }
            return false
        }

        var isNumber = true
        if isDigit(lexer.lookahead) {
            Self.advance(&lexer)
        } else if isAlpha(lexer.lookahead) || lexer.lookahead == 0x5F {
            isNumber = false
            Self.advance(&lexer)
        } else {
            if lexer.lookahead == 0x7B { return scanBraceStart(&lexer, validSymbols: valid) }
            if valid[.expansionWord] { return scanExpansionWord(&lexer) }
            if valid[.extglobPattern] { return scanExtglobPattern(&lexer, validSymbols: valid) }
            return false
        }

        while true {
            if isDigit(lexer.lookahead) {
                Self.advance(&lexer)
            } else if isAlpha(lexer.lookahead) || lexer.lookahead == 0x5F {
                isNumber = false
                Self.advance(&lexer)
            } else {
                break
            }
        }

        if isNumber && valid[.fileDescriptor] && (lexer.lookahead == 0x3E || lexer.lookahead == 0x3C) {
            Self.emit(.fileDescriptor, &lexer)
            return true
        }

        if valid[.variableName] {
            if lexer.lookahead == 0x2B {
                lexer.markEnd()
                Self.advance(&lexer)
                if lexer.lookahead == 0x3D || lexer.lookahead == 0x3A || valid[.closingBrace] {
                    Self.emit(.variableName, &lexer)
                    return true
                }
                return false
            }
            if lexer.lookahead == 0x2F { return false }
            if lexer.lookahead == 0x3D || lexer.lookahead == 0x5B
                || (lexer.lookahead == 0x3A && !valid[.closingBrace] && !valid[.openingParen])
                || lexer.lookahead == 0x25 || (lexer.lookahead == 0x23 && !isNumber)
                || lexer.lookahead == 0x40 || (lexer.lookahead == 0x2D && valid[.closingBrace])
            {
                lexer.markEnd()
                Self.emit(.variableName, &lexer)
                return true
            }
            if lexer.lookahead == 0x3F {
                lexer.markEnd()
                Self.advance(&lexer)
                Self.emit(.variableName, &lexer)
                return isAlpha(lexer.lookahead)
            }
        }
        return false
    }
}
