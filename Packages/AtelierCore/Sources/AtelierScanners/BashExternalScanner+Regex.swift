import AtelierParser

private func isSpace(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isWhitespace ?? false }

private func isAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

extension BashExternalScanner {
    // Mirrors the upstream C function branch for branch, so the port stays comparable with it line by line.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanRegex(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard (valid[.regex] || valid[.regexNoSlash] || valid[.regexNoSpace]) && !valid[.errorRecovery]
        else { return false }
        if valid[.regex] || valid[.regexNoSpace] {
            while isSpace(lexer.lookahead) { Self.skip(&lexer) }
        }
        guard
            (lexer.lookahead != 0x22 && lexer.lookahead != 0x27)
                || ((lexer.lookahead == 0x24 || lexer.lookahead == 0x27) && valid[.regexNoSlash])
                || (lexer.lookahead == 0x27 && valid[.regexNoSpace])
        else { return false }

        if lexer.lookahead == 0x24 && valid[.regexNoSlash] {
            lexer.markEnd()
            Self.advance(&lexer)
            if lexer.lookahead == 0x28 { return false }
        }
        lexer.markEnd()
        var done = false
        var advancedOnce = false
        var foundNonAlnumDollarUnderDash = false
        var lastWasEscape = false
        var inSingleQuote = false
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        while !done {
            if inSingleQuote && lexer.lookahead == 0x27 {
                inSingleQuote = false
                Self.advance(&lexer)
                lexer.markEnd()
            }
            switch lexer.lookahead {
                case 0x5C:
                    lastWasEscape = true
                case 0:
                    return false
                case 0x28:
                    parenDepth += 1
                    lastWasEscape = false
                case 0x5B:
                    bracketDepth += 1
                    lastWasEscape = false
                case 0x7B:
                    if !lastWasEscape { braceDepth += 1 }
                    lastWasEscape = false
                case 0x29:
                    if parenDepth == 0 { done = true }
                    parenDepth -= 1
                    lastWasEscape = false
                case 0x5D:
                    if bracketDepth == 0 { done = true }
                    bracketDepth -= 1
                    lastWasEscape = false
                case 0x7D:
                    if braceDepth == 0 { done = true }
                    braceDepth -= 1
                    lastWasEscape = false
                case 0x27:
                    // Enter or exit a single-quoted string.
                    inSingleQuote = !inSingleQuote
                    Self.advance(&lexer)
                    advancedOnce = true
                    lastWasEscape = false
                    continue
                default:
                    lastWasEscape = false
            }

            if !done {
                if valid[.regex] {
                    let wasSpace = !inSingleQuote && isSpace(lexer.lookahead)
                    Self.advance(&lexer)
                    advancedOnce = true
                    if !wasSpace || parenDepth > 0 { lexer.markEnd() }
                } else if valid[.regexNoSlash] {
                    if lexer.lookahead == 0x2F {
                        lexer.markEnd()
                        Self.emit(.regexNoSlash, &lexer)
                        return advancedOnce
                    }
                    if lexer.lookahead == 0x5C {
                        Self.advance(&lexer)
                        advancedOnce = true
                        if !lexer.isAtEnd && lexer.lookahead != 0x5B && lexer.lookahead != 0x2F {
                            Self.advance(&lexer)
                            lexer.markEnd()
                        }
                    } else {
                        let wasSpace = !inSingleQuote && isSpace(lexer.lookahead)
                        Self.advance(&lexer)
                        advancedOnce = true
                        if !wasSpace { lexer.markEnd() }
                    }
                } else if valid[.regexNoSpace] {
                    if lexer.lookahead == 0x5C {
                        foundNonAlnumDollarUnderDash = true
                        Self.advance(&lexer)
                        if !lexer.isAtEnd { Self.advance(&lexer) }
                    } else if lexer.lookahead == 0x24 {
                        lexer.markEnd()
                        Self.advance(&lexer)
                        // Do not parse a command substitution.
                        if lexer.lookahead == 0x28 { return false }
                        // End $ always means regex, e.g. 99999999$.
                        if isSpace(lexer.lookahead) {
                            Self.emit(.regexNoSpace, &lexer)
                            lexer.markEnd()
                            return true
                        }
                    } else {
                        let wasSpace = !inSingleQuote && isSpace(lexer.lookahead)
                        if wasSpace && parenDepth == 0 {
                            lexer.markEnd()
                            Self.emit(.regexNoSpace, &lexer)
                            return foundNonAlnumDollarUnderDash
                        }
                        if !isAlnum(lexer.lookahead) && lexer.lookahead != 0x24
                            && lexer.lookahead != 0x2D && lexer.lookahead != 0x5F
                        {
                            foundNonAlnumDollarUnderDash = true
                        }
                        Self.advance(&lexer)
                    }
                }
            }
        }
        Self.emit(valid[.regexNoSlash] ? .regexNoSlash : valid[.regexNoSpace] ? .regexNoSpace : .regex, &lexer)
        if valid[.regex] && !advancedOnce { return false }
        return true
    }
}
