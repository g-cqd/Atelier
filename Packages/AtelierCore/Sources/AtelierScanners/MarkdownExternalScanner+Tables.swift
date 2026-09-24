import AtelierParser

extension MarkdownExternalScanner {
    private static func isPunctuation(_ scalar: UInt32) -> Bool {
        (33 ... 47).contains(scalar) || (58 ... 64).contains(scalar)
            || (91 ... 96).contains(scalar) || (123 ... 126).contains(scalar)
    }

    // Preserve the source scanner's delimiter-row branch order.
    // swiftlint:disable:next cyclomatic_complexity
    mutating func parsePipeTable(_ lexer: inout some ScannerLexer) -> Bool {
        // PIPE_TABLE_START is zero width.
        markEnd(&lexer)
        var cellCount = 0
        var startingPipe = false
        var endingPipe = false
        let empty = true  // Kept as in the upstream scanner.
        if lexer.lookahead == 124 {
            startingPipe = true
            advance(&lexer)
        }
        while !Self.isNewline(lexer.lookahead) && !lexer.isAtEnd {
            if lexer.lookahead == 124 {
                cellCount += 1
                endingPipe = true
                advance(&lexer)
            } else {
                if lexer.lookahead != 32 && lexer.lookahead != 9 { endingPipe = false }
                if lexer.lookahead == 92 {
                    advance(&lexer)
                    if Self.isPunctuation(lexer.lookahead) { advance(&lexer) }
                } else {
                    advance(&lexer)
                }
            }
        }
        if empty && cellCount == 0 && !(startingPipe && endingPipe) { return false }
        if !endingPipe { cellCount += 1 }
        guard Self.isNewline(lexer.lookahead) else { return false }
        advanceNewline(&lexer)
        indentation = 0
        column = 0
        while lexer.lookahead == 32 || lexer.lookahead == 9 { indentation = (indentation + advance(&lexer)) & 0xFF }
        simulate = true
        var matchedTemp = 0
        while matchedTemp < openBlocks.count {
            guard match(openBlocks[matchedTemp], &lexer) else { return false }
            matchedTemp += 1
        }
        var delimiterCellCount = 0
        if lexer.lookahead == 124 { advance(&lexer) }
        while true {
            while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
            if lexer.lookahead == 124 {
                delimiterCellCount += 1
                advance(&lexer)
                continue
            }
            if lexer.lookahead == 58 {
                advance(&lexer)
                guard lexer.lookahead == 45 else { return false }
            }
            var hadOneMinus = false
            while lexer.lookahead == 45 {
                hadOneMinus = true
                advance(&lexer)
            }
            if hadOneMinus { delimiterCellCount += 1 }
            if lexer.lookahead == 58 {
                guard hadOneMinus else { return false }
                advance(&lexer)
            }
            while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
            if lexer.lookahead == 124 {
                if !hadOneMinus { delimiterCellCount += 1 }
                advance(&lexer)
                continue
            }
            guard Self.isNewline(lexer.lookahead) else { return false }
            break
        }
        guard cellCount == delimiterCellCount else { return false }
        lexer.resultSymbol = Token.pipeTableStart.rawValue
        return true
    }
}
