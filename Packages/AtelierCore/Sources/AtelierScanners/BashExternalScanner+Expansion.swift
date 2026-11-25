import AtelierParser

private func isSpace(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isWhitespace ?? false }

private func isAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

private func isDigit(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.generalCategory == .decimalNumber }

extension BashExternalScanner {
    mutating func scanExpansionWord(_ lexer: inout some ScannerLexer) -> Bool {
        var advancedOnce = false
        var advanceOnceSpace = false
        while true {
            if lexer.lookahead == 0x22 { return false }
            if lexer.lookahead == 0x24 {
                lexer.markEnd()
                Self.advance(&lexer)
                if lexer.lookahead == 0x7B || lexer.lookahead == 0x28 || lexer.lookahead == 0x27
                    || isAlnum(lexer.lookahead)
                {
                    Self.emit(.expansionWord, &lexer)
                    return advancedOnce
                }
                advancedOnce = true
            }
            if lexer.lookahead == 0x7D {
                lexer.markEnd()
                Self.emit(.expansionWord, &lexer)
                return advancedOnce || advanceOnceSpace
            }
            if lexer.lookahead == 0x28 && !(advancedOnce || advanceOnceSpace) {
                lexer.markEnd()
                Self.advance(&lexer)
                while lexer.lookahead != 0x29 && !lexer.isAtEnd {
                    // If we find a $( or ${ assume this is valid and is
                    // a garbage concatenation of some weird word + an
                    // expansion. I wonder where this can fail.
                    if lexer.lookahead == 0x24 {
                        lexer.markEnd()
                        Self.advance(&lexer)
                        if lexer.lookahead == 0x7B || lexer.lookahead == 0x28 || lexer.lookahead == 0x27
                            || isAlnum(lexer.lookahead)
                        {
                            Self.emit(.expansionWord, &lexer)
                            return advancedOnce
                        }
                        advancedOnce = true
                    } else {
                        advancedOnce = advancedOnce || !isSpace(lexer.lookahead)
                        advanceOnceSpace = advanceOnceSpace || isSpace(lexer.lookahead)
                        Self.advance(&lexer)
                    }
                }
                lexer.markEnd()
                guard lexer.lookahead == 0x29 else {
                    return false
                }
                advancedOnce = true
                Self.advance(&lexer)
                lexer.markEnd()
                if lexer.lookahead == 0x7D { return false }
            }
            if lexer.lookahead == 0x27 || lexer.isAtEnd { return false }
            advancedOnce = advancedOnce || !isSpace(lexer.lookahead)
            advanceOnceSpace = advanceOnceSpace || isSpace(lexer.lookahead)
            Self.advance(&lexer)
        }
    }

    mutating func scanBraceStart(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard valid[.braceStart] && !valid[.errorRecovery] else { return false }
        while isSpace(lexer.lookahead) { Self.skip(&lexer) }
        guard lexer.lookahead == 0x7B else { return false }
        Self.advance(&lexer)
        lexer.markEnd()
        while isDigit(lexer.lookahead) { Self.advance(&lexer) }
        guard lexer.lookahead == 0x2E else { return false }
        Self.advance(&lexer)
        guard lexer.lookahead == 0x2E else { return false }
        Self.advance(&lexer)
        while isDigit(lexer.lookahead) { Self.advance(&lexer) }
        guard lexer.lookahead == 0x7D else { return false }
        Self.emit(.braceStart, &lexer)
        return true
    }
}
