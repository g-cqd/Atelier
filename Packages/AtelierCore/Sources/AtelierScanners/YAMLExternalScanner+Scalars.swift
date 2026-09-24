import AtelierParser

private func c(_ value: Unicode.Scalar) -> UInt32 { value.value }

extension YAMLExternalScanner {
    mutating func advanceSchemaState() -> Bool {
        guard let next = Self.advanceSchema(schStt, curChr, result: &rltSch) else { return false }
        schStt = next
        return true
    }

    // Preserve the C header, indentation indicator, and chomping branch order.
    // swiftlint:disable:next cyclomatic_complexity
    mutating func scanBlockStringBeginning(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard lexer.lookahead == c("|") || lexer.lookahead == c(">") else { return false }
        adv(&lexer)
        let currentIndent = indLenStack[indLenStack.count - 1]
        var indent = -1
        if c("1") <= lexer.lookahead && lexer.lookahead <= c("9") {
            indent = Int(lexer.lookahead - c("1"))
            adv(&lexer)
            if lexer.lookahead == c("+") || lexer.lookahead == c("-") { adv(&lexer) }
        } else if lexer.lookahead == c("+") || lexer.lookahead == c("-") {
            adv(&lexer)
            if c("1") <= lexer.lookahead && lexer.lookahead <= c("9") {
                indent = Int(lexer.lookahead - c("1"))
                adv(&lexer)
            }
        }
        guard Self.isWht(lexer.lookahead) else { return false }
        mrkEnd(&lexer)
        if indent != -1 {
            indent += currentIndent
        } else {
            indent = currentIndent
            while Self.isWsp(lexer.lookahead) { adv(&lexer) }
            if lexer.lookahead == c("#") {
                adv(&lexer)
                while !Self.isNwl(lexer.lookahead) && lexer.lookahead != 0 { adv(&lexer) }
            }
            if Self.isNwl(lexer.lookahead) { advNwl(&lexer) }
            while lexer.lookahead != 0 {
                if lexer.lookahead == c(" ") {
                    adv(&lexer)
                } else if Self.isNwl(lexer.lookahead) {
                    if curCol - 1 < indent { break }
                    indent = curCol - 1
                    advNwl(&lexer)
                } else {
                    if curCol - 1 > indent { indent = curCol - 1 }
                    break
                }
            }
        }
        pushInd(Self.indStr, indent)
        return emit(symbol, &lexer)
    }

    mutating func scanBlockStringContent(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard Self.isNsChar(lexer.lookahead) else { return false }
        if curCol == 0 && scanDocumentEnd(&lexer) {
            guard popInd() else { return false }
            return emit(.bl, &lexer)
        } else {
            adv(&lexer)
        }
        mrkEnd(&lexer)
        while true {
            if Self.isNsChar(lexer.lookahead) {
                adv(&lexer)
                while Self.isNsChar(lexer.lookahead) { adv(&lexer) }
                mrkEnd(&lexer)
            }
            guard Self.isWsp(lexer.lookahead) else { break }
            adv(&lexer)
            while Self.isWsp(lexer.lookahead) { adv(&lexer) }
        }
        return emit(symbol, &lexer)
    }

    mutating func scanPlainContent(_ lexer: inout some ScannerLexer, inBlock: Bool) -> Int {
        func isSafe(_ char: UInt32) -> Bool {
            inBlock ? Self.isPlainSafeBlock(char) : Self.isPlainSafeFlow(char)
        }
        var isCurrentSafe = isSafe(curChr)
        var isLookaheadWsp = Self.isWsp(lexer.lookahead)
        var isLookaheadSafe = isSafe(lexer.lookahead)
        guard isLookaheadSafe || isLookaheadWsp else { return Self.scanStop }
        while true {
            if isLookaheadSafe && lexer.lookahead != c("#") && lexer.lookahead != c(":") {
                adv(&lexer)
                mrkEnd(&lexer)
                guard advanceSchemaState() else { return Self.scanFailure }
            } else if isCurrentSafe && lexer.lookahead == c("#") {
                adv(&lexer)
                mrkEnd(&lexer)
                guard advanceSchemaState() else { return Self.scanFailure }
            } else if isLookaheadWsp {
                adv(&lexer)
                guard advanceSchemaState() else { return Self.scanFailure }
            } else if lexer.lookahead == c(":") {
                adv(&lexer)  // Check whether a safe character follows.
            } else {
                break
            }

            isCurrentSafe = isLookaheadSafe
            isLookaheadWsp = Self.isWsp(lexer.lookahead)
            isLookaheadSafe = isSafe(lexer.lookahead)
            if curChr == c(":") {
                guard isLookaheadSafe else { return Self.scanFailure }
                mrkEnd(&lexer)
                guard advanceSchemaState() else { return Self.scanFailure }
            }
        }
        return Self.scanSuccess
    }

    func plainSymbol(position: Int, inBlock: Bool) -> TokenType? {
        let base: Int
        if inBlock {
            base =
                position == 0
                ? TokenType.r_sgl_pln_nul_blk.rawValue
                : position == 1
                    ? TokenType.br_sgl_pln_nul_blk.rawValue
                    : TokenType.b_sgl_pln_nul_blk.rawValue
        } else {
            base = position == 0 ? TokenType.r_sgl_pln_nul_flw.rawValue : TokenType.br_sgl_pln_nul_flw.rawValue
        }
        let offset: Int
        switch rltSch {
            case .null: offset = 0
            case .boolean: offset = 5
            case .integer: offset = 10
            case .float: offset = 15
            case .string: offset = 25
        }
        return TokenType(rawValue: base + offset)
    }
}
