import AtelierParser

private func isSpace(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isWhitespace ?? false }

private func isAlpha(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isAlphabetic ?? false }

private func isAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

extension BashExternalScanner {
    // Mirrors the upstream C function branch for branch, so the port stays comparable with it line by line.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanExtglobPattern(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard valid[.extglobPattern] && !valid[.errorRecovery] else { return false }
        // First skip whitespace, then check for ? * + @ !.
        while isSpace(lexer.lookahead) { Self.skip(&lexer) }
        guard
            [0x3F, 0x2A, 0x2B, 0x40, 0x21, 0x2D, 0x29, 0x5C, 0x2E, 0x5B].contains(lexer.lookahead)
                || isAlpha(lexer.lookahead)
        else {
            lastGlobParenDepth = 0
            return false
        }
        if lexer.lookahead == 0x5C {
            Self.advance(&lexer)
            guard
                (isSpace(lexer.lookahead) || lexer.lookahead == 0x22)
                    && lexer.lookahead != 0x0D && lexer.lookahead != 0x0A
            else {
                return false
            }
            Self.advance(&lexer)
        }
        if lexer.lookahead == 0x29 && lastGlobParenDepth == 0 {
            lexer.markEnd()
            Self.advance(&lexer)
            if isSpace(lexer.lookahead) { return false }
        }
        lexer.markEnd()
        let wasNonAlpha = !isAlpha(lexer.lookahead)
        if lexer.lookahead != 0x5B {
            // No esac.
            if lexer.lookahead == 0x65 {
                lexer.markEnd()
                Self.advance(&lexer)
                if lexer.lookahead == 0x73 {
                    Self.advance(&lexer)
                    if lexer.lookahead == 0x61 {
                        Self.advance(&lexer)
                        if lexer.lookahead == 0x63 {
                            Self.advance(&lexer)
                            if isSpace(lexer.lookahead) { return false }
                        }
                    }
                }
            } else {
                Self.advance(&lexer)
            }
        }

        // -\w is just a word; find something else special.
        if lexer.lookahead == 0x2D {
            lexer.markEnd()
            Self.advance(&lexer)
            while isAlnum(lexer.lookahead) { Self.advance(&lexer) }
            if lexer.lookahead == 0x29 || lexer.lookahead == 0x5C || lexer.lookahead == 0x2E { return false }
            lexer.markEnd()
        }

        // Case item -) or *).
        if lexer.lookahead == 0x29 && lastGlobParenDepth == 0 {
            lexer.markEnd()
            Self.advance(&lexer)
            if isSpace(lexer.lookahead) {
                Self.emit(.extglobPattern, &lexer)
                return wasNonAlpha
            }
        }
        if isSpace(lexer.lookahead) {
            lexer.markEnd()
            Self.emit(.extglobPattern, &lexer)
            lastGlobParenDepth = 0
            return true
        }
        if lexer.lookahead == 0x24 {
            lexer.markEnd()
            Self.advance(&lexer)
            if lexer.lookahead == 0x7B || lexer.lookahead == 0x28 {
                Self.emit(.extglobPattern, &lexer)
                return true
            }
        }
        if lexer.lookahead == 0x7C {
            lexer.markEnd()
            Self.advance(&lexer)
            Self.emit(.extglobPattern, &lexer)
            return true
        }
        if !isAlnum(lexer.lookahead)
            && ![0x28, 0x22, 0x5B, 0x3F, 0x2F, 0x5C, 0x5F, 0x2A].contains(lexer.lookahead)
        {
            return false
        }

        var done = false
        var sawNonAlphaDot = wasNonAlpha
        var parenDepth = Int(lastGlobParenDepth)
        var bracketDepth = 0
        var braceDepth = 0
        while !done {
            switch lexer.lookahead {
                case 0: return false
                case 0x28: parenDepth += 1
                case 0x5B: bracketDepth += 1
                case 0x7B: braceDepth += 1
                case 0x29:
                    if parenDepth == 0 { done = true }
                    parenDepth -= 1
                case 0x5D:
                    if bracketDepth == 0 { done = true }
                    bracketDepth -= 1
                case 0x7D:
                    if braceDepth == 0 { done = true }
                    braceDepth -= 1
                default: break
            }
            if lexer.lookahead == 0x7C {
                lexer.markEnd()
                Self.advance(&lexer)
                if parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 {
                    Self.emit(.extglobPattern, &lexer)
                    return true
                }
            }
            if !done {
                let wasSpace = isSpace(lexer.lookahead)
                if lexer.lookahead == 0x24 {
                    lexer.markEnd()
                    if !isAlpha(lexer.lookahead) && lexer.lookahead != 0x2E && lexer.lookahead != 0x5C {
                        sawNonAlphaDot = true
                    }
                    Self.advance(&lexer)
                    if lexer.lookahead == 0x28 || lexer.lookahead == 0x7B {
                        Self.emit(.extglobPattern, &lexer)
                        lastGlobParenDepth = UInt8(truncatingIfNeeded: parenDepth)
                        return sawNonAlphaDot
                    }
                }
                if wasSpace {
                    lexer.markEnd()
                    Self.emit(.extglobPattern, &lexer)
                    lastGlobParenDepth = 0
                    return sawNonAlphaDot
                }
                if lexer.lookahead == 0x22 {
                    lexer.markEnd()
                    Self.emit(.extglobPattern, &lexer)
                    lastGlobParenDepth = 0
                    return sawNonAlphaDot
                }
                if lexer.lookahead == 0x5C {
                    if !isAlpha(lexer.lookahead) && lexer.lookahead != 0x2E && lexer.lookahead != 0x5C {
                        sawNonAlphaDot = true
                    }
                    Self.advance(&lexer)
                    if isSpace(lexer.lookahead) || lexer.lookahead == 0x22 { Self.advance(&lexer) }
                } else {
                    if !isAlpha(lexer.lookahead) && lexer.lookahead != 0x2E && lexer.lookahead != 0x5C {
                        sawNonAlphaDot = true
                    }
                    Self.advance(&lexer)
                }
                if !wasSpace { lexer.markEnd() }
            }
        }
        Self.emit(.extglobPattern, &lexer)
        lastGlobParenDepth = 0
        return sawNonAlphaDot
    }
}
