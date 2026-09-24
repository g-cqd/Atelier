import AtelierParser

private func isSpace(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isWhitespace ?? false }

private func isAlpha(_ value: UInt32) -> Bool { Unicode.Scalar(value)?.properties.isAlphabetic ?? false }

extension BashExternalScanner {
    /// Consume a "word" in POSIX parlance, and return it unquoted.
    /// This is an approximate implementation that doesn't deal with any
    /// POSIX-mandated substitution, and assumes the default value for IFS.
    static func advanceWord(_ lexer: inout some ScannerLexer, unquotedWord: inout [UInt8]) -> Bool {
        var empty = true
        var quote: UInt32 = 0
        if lexer.lookahead == 0x27 || lexer.lookahead == 0x22 {
            quote = lexer.lookahead
            advance(&lexer)
        }
        while lexer.lookahead != 0
            && (quote != 0
                ? lexer.lookahead != quote && lexer.lookahead != 0x0D && lexer.lookahead != 0x0A
                : !isSpace(lexer.lookahead))
        {
            if lexer.lookahead == 0x5C {
                advance(&lexer)
                if lexer.lookahead == 0 { return false }
            }
            empty = false
            unquotedWord.append(UInt8(truncatingIfNeeded: lexer.lookahead))
            advance(&lexer)
        }
        unquotedWord.append(0)
        if quote != 0 && lexer.lookahead == quote { advance(&lexer) }
        return !empty
    }

    static func scanBareDollar(_ lexer: inout some ScannerLexer) -> Bool {
        while isSpace(lexer.lookahead) && lexer.lookahead != 0x0A && !lexer.isAtEnd { skip(&lexer) }
        if lexer.lookahead == 0x24 {
            advance(&lexer)
            emit(.bareDollar, &lexer)
            lexer.markEnd()
            return isSpace(lexer.lookahead) || lexer.isAtEnd || lexer.lookahead == 0x22
        }
        return false
    }

    mutating func scanHeredocStart(_ lexer: inout some ScannerLexer) -> Bool {
        while isSpace(lexer.lookahead) { Self.skip(&lexer) }
        Self.emit(.heredocStart, &lexer)
        let index = heredocs.count - 1
        heredocs[index].isRaw = lexer.lookahead == 0x27 || lexer.lookahead == 0x22 || lexer.lookahead == 0x5C
        let found = Self.advanceWord(&lexer, unquotedWord: &heredocs[index].delimiter)
        if !found { heredocs[index].delimiter.removeAll(keepingCapacity: true) }
        return found
    }

    mutating func scanHeredocEndIdentifier(_ lexer: inout some ScannerLexer) -> Bool {
        let index = heredocs.count - 1
        heredocs[index].currentLeadingWord.removeAll(keepingCapacity: true)
        // Scan the first 'n' characters on this line, to see if they match the
        // heredoc delimiter.
        var size = 0
        if !heredocs[index].delimiter.isEmpty {
            while lexer.lookahead != 0 && lexer.lookahead != 0x0A
                && size < heredocs[index].delimiter.count
                && UInt32(heredocs[index].delimiter[size]) == lexer.lookahead
                && heredocs[index].currentLeadingWord.count < heredocs[index].delimiter.count
            {
                heredocs[index].currentLeadingWord.append(UInt8(truncatingIfNeeded: lexer.lookahead))
                Self.advance(&lexer)
                size += 1
            }
        }
        heredocs[index].currentLeadingWord.append(0)
        guard !heredocs[index].delimiter.isEmpty else { return false }
        return heredocs[index].currentLeadingWord == heredocs[index].delimiter
    }

    // Mirrors the upstream C function branch for branch, so the port stays comparable with it line by line.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanHeredocContent(
        _ lexer: inout some ScannerLexer, middleType: TokenType, endType: TokenType
    ) -> Bool {
        var didAdvance = false
        let index = heredocs.count - 1
        while true {
            switch lexer.lookahead {
                case 0:
                    if lexer.isAtEnd && didAdvance {
                        heredocs[index].isRaw = false
                        heredocs[index].started = false
                        heredocs[index].allowsIndent = false
                        heredocs[index].delimiter.removeAll(keepingCapacity: true)
                        Self.emit(endType, &lexer)
                        return true
                    }
                    return false
                case 0x5C:
                    didAdvance = true
                    Self.advance(&lexer)
                    Self.advance(&lexer)
                case 0x24:
                    if heredocs[index].isRaw {
                        didAdvance = true
                        Self.advance(&lexer)
                        break
                    }
                    if didAdvance {
                        lexer.markEnd()
                        Self.emit(middleType, &lexer)
                        heredocs[index].started = true
                        Self.advance(&lexer)
                        if isAlpha(lexer.lookahead) || lexer.lookahead == 0x7B || lexer.lookahead == 0x28 {
                            return true
                        }
                        break
                    }
                    if middleType == .heredocBodyBeginning && lexer.column() == 0 {
                        Self.emit(middleType, &lexer)
                        heredocs[index].started = true
                        return true
                    }
                    return false
                case 0x0A:
                    if !didAdvance { Self.skip(&lexer) } else { Self.advance(&lexer) }
                    didAdvance = true
                    if heredocs[index].allowsIndent {
                        while isSpace(lexer.lookahead) { Self.advance(&lexer) }
                    }
                    Self.emit(heredocs[index].started ? middleType : endType, &lexer)
                    lexer.markEnd()
                    if scanHeredocEndIdentifier(&lexer) {
                        if lexer.resultSymbol == TokenType.heredocEnd.rawValue { heredocs.removeLast() }
                        return true
                    }
                default:
                    if lexer.column() == 0 {
                        // An alternative is to check the starting column of the
                        // heredoc body and track that statefully.
                        while isSpace(lexer.lookahead) {
                            if didAdvance { Self.advance(&lexer) } else { Self.skip(&lexer) }
                        }
                        if endType != .simpleHeredocBody {
                            Self.emit(middleType, &lexer)
                            if scanHeredocEndIdentifier(&lexer) { return true }
                        }
                        if endType == .simpleHeredocBody {
                            Self.emit(endType, &lexer)
                            lexer.markEnd()
                            if scanHeredocEndIdentifier(&lexer) { return true }
                        }
                    }
                    didAdvance = true
                    Self.advance(&lexer)
            }
        }
    }
}
