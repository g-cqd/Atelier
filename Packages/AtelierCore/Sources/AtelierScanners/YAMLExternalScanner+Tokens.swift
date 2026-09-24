import AtelierParser

private func c(_ value: Unicode.Scalar) -> UInt32 { value.value }

extension YAMLExternalScanner {
    static func isWsp(_ char: UInt32) -> Bool { char == c(" ") || char == c("\t") }
    static func isNwl(_ char: UInt32) -> Bool { char == c("\r") || char == c("\n") }
    static func isWht(_ char: UInt32) -> Bool { isWsp(char) || isNwl(char) || char == 0 }
    static func isDecDigit(_ char: UInt32) -> Bool { c("0") <= char && char <= c("9") }
    static func isHexDigit(_ char: UInt32) -> Bool {
        isDecDigit(char) || (c("a") <= char && char <= c("f")) || (c("A") <= char && char <= c("F"))
    }
    static func isWordChar(_ char: UInt32) -> Bool {
        char == c("-") || isDecDigit(char) || (c("a") <= char && char <= c("z"))
            || (c("A") <= char && char <= c("Z"))
    }
    static func isNbJSON(_ char: UInt32) -> Bool { char == c("\t") || (0x20 <= char && char <= 0x10FFFF) }
    static func isNbDoubleChar(_ char: UInt32) -> Bool { isNbJSON(char) && char != c("\\") && char != c("\"") }
    static func isNbSingleChar(_ char: UInt32) -> Bool { isNbJSON(char) && char != c("'") }
    static func isNsChar(_ char: UInt32) -> Bool {
        (0x21 ... 0x7E).contains(char) || char == 0x85 || (0xA0 ... 0xD7FF).contains(char)
            || (0xE000 ... 0xFEFE).contains(char) || (0xFF00 ... 0xFFFD).contains(char)
            || (0x10000 ... 0x10FFFF).contains(char)
    }
    static func isIndicator(_ char: UInt32) -> Bool {
        "-?:,[]{}#&*!|>'\"%@`".unicodeScalars.contains { $0.value == char }
    }
    static func isFlowIndicator(_ char: UInt32) -> Bool {
        ",[{}]".unicodeScalars.contains { $0.value == char }
    }
    static func isPlainSafeBlock(_ char: UInt32) -> Bool { isNsChar(char) }
    static func isPlainSafeFlow(_ char: UInt32) -> Bool { isNsChar(char) && !isFlowIndicator(char) }
    static func isUriChar(_ char: UInt32) -> Bool {
        isWordChar(char) || "#;/?:@&=+$,_.!~*'()[]".unicodeScalars.contains { $0.value == char }
    }
    static func isTagChar(_ char: UInt32) -> Bool {
        isWordChar(char) || "#;/?:@&=+$,_.~*'()".unicodeScalars.contains { $0.value == char }
    }
    static func isAnchorChar(_ char: UInt32) -> Bool { isNsChar(char) && !isFlowIndicator(char) }

    mutating func scanUriEscape(_ lexer: inout some ScannerLexer) -> Int {
        guard lexer.lookahead == c("%") else { return Self.scanStop }
        mrkEnd(&lexer)
        adv(&lexer)
        guard Self.isHexDigit(lexer.lookahead) else { return Self.scanFailure }
        adv(&lexer)
        guard Self.isHexDigit(lexer.lookahead) else { return Self.scanFailure }
        adv(&lexer)
        return Self.scanSuccess
    }

    mutating func scanUriChar(_ lexer: inout some ScannerLexer) -> Int {
        if Self.isUriChar(lexer.lookahead) {
            adv(&lexer)
            return Self.scanSuccess
        }
        return scanUriEscape(&lexer)
    }

    mutating func scanTagChar(_ lexer: inout some ScannerLexer) -> Int {
        if Self.isTagChar(lexer.lookahead) {
            adv(&lexer)
            return Self.scanSuccess
        }
        return scanUriEscape(&lexer)
    }

    mutating func scanDirectiveBeginning(_ lexer: inout some ScannerLexer) -> Bool {
        adv(&lexer)
        if lexer.lookahead == c("Y") {
            adv(&lexer)
            if lexer.lookahead == c("A") {
                adv(&lexer)
                if lexer.lookahead == c("M") {
                    adv(&lexer)
                    if lexer.lookahead == c("L") {
                        adv(&lexer)
                        if Self.isWht(lexer.lookahead) {
                            mrkEnd(&lexer)
                            return emit(.s_dir_yml_bgn, &lexer)
                        }
                    }
                }
            }
        } else if lexer.lookahead == c("T") {
            adv(&lexer)
            if lexer.lookahead == c("A") {
                adv(&lexer)
                if lexer.lookahead == c("G") {
                    adv(&lexer)
                    if Self.isWht(lexer.lookahead) {
                        mrkEnd(&lexer)
                        return emit(.s_dir_tag_bgn, &lexer)
                    }
                }
            }
        }
        while Self.isNsChar(lexer.lookahead) { adv(&lexer) }
        if curCol > 1 && Self.isWht(lexer.lookahead) {
            mrkEnd(&lexer)
            return emit(.s_dir_rsv_bgn, &lexer)
        }
        return false
    }

    mutating func scanDirectiveVersion(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        var n1 = 0
        var n2 = 0
        while Self.isDecDigit(lexer.lookahead) {
            adv(&lexer)
            n1 += 1
        }
        guard lexer.lookahead == c(".") else { return false }
        adv(&lexer)
        while Self.isDecDigit(lexer.lookahead) {
            adv(&lexer)
            n2 += 1
        }
        guard n1 > 0, n2 > 0 else { return false }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanTagHandleTail(_ lexer: inout some ScannerLexer) -> Bool {
        if lexer.lookahead == c("!") {
            adv(&lexer)
            return true
        }
        var count = 0
        while Self.isWordChar(lexer.lookahead) {
            adv(&lexer)
            count += 1
        }
        if count == 0 { return true }
        if lexer.lookahead == c("!") {
            adv(&lexer)
            return true
        }
        return false
    }

    mutating func scanDirectiveTagHandle(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        if lexer.lookahead == c("!") {
            adv(&lexer)
            if scanTagHandleTail(&lexer) {
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        }
        return false
    }

    mutating func scanDirectiveTagPrefix(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        if lexer.lookahead == c("!") { adv(&lexer) } else if scanTagChar(&lexer) != Self.scanSuccess { return false }
        while true {
            let result = scanUriChar(&lexer)
            if result == Self.scanStop { mrkEnd(&lexer) }
            if result != Self.scanSuccess { return emit(symbol, &lexer) }
        }
    }

    mutating func scanDirectiveReservedParameter(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard Self.isNsChar(lexer.lookahead) else { return false }
        adv(&lexer)
        while Self.isNsChar(lexer.lookahead) { adv(&lexer) }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanTag(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard lexer.lookahead == c("!") else { return false }
        adv(&lexer)
        if Self.isWht(lexer.lookahead) {
            mrkEnd(&lexer)
            return emit(symbol, &lexer)
        }
        if lexer.lookahead == c("<") {
            adv(&lexer)
            guard scanUriChar(&lexer) == Self.scanSuccess else { return false }
            while true {
                let result = scanUriChar(&lexer)
                if result == Self.scanStop, lexer.lookahead == c(">") {
                    adv(&lexer)
                    mrkEnd(&lexer)
                    return emit(symbol, &lexer)
                }
                if result != Self.scanSuccess { return false }
            }
        } else {
            if scanTagHandleTail(&lexer) && scanTagChar(&lexer) != Self.scanSuccess { return false }
            while true {
                let result = scanTagChar(&lexer)
                if result == Self.scanStop { mrkEnd(&lexer) }
                if result != Self.scanSuccess { return emit(symbol, &lexer) }
            }
        }
    }

    mutating func scanAnchorBeginning(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard lexer.lookahead == c("&") else { return false }
        adv(&lexer)
        guard Self.isAnchorChar(lexer.lookahead) else { return false }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanAnchorContent(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        while Self.isAnchorChar(lexer.lookahead) { adv(&lexer) }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanAliasBeginning(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard lexer.lookahead == c("*") else { return false }
        adv(&lexer)
        guard Self.isAnchorChar(lexer.lookahead) else { return false }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanAliasContent(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        while Self.isAnchorChar(lexer.lookahead) { adv(&lexer) }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanDoubleEscape(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        switch lexer.lookahead {
            case c("0"), c("a"), c("b"), c("t"), c("\t"), c("n"), c("v"), c("r"), c("e"), c("f"),
                c(" "), c("\""), c("/"), c("\\"), c("N"), c("_"), c("L"), c("P"):
                adv(&lexer)
            case c("U"), c("u"), c("x"):
                let count = lexer.lookahead == c("U") ? 8 : lexer.lookahead == c("u") ? 4 : 2
                adv(&lexer)
                for _ in 0 ..< count {
                    guard Self.isHexDigit(lexer.lookahead) else { return false }
                    adv(&lexer)
                }
            default:
                return false
        }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanDocumentEnd(_ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == c("-") || lexer.lookahead == c(".") else { return false }
        let delimiter = lexer.lookahead
        adv(&lexer)
        if lexer.lookahead == delimiter {
            adv(&lexer)
            if lexer.lookahead == delimiter {
                adv(&lexer)
                if Self.isWht(lexer.lookahead) { return true }
            }
        }
        mrkEnd(&lexer)
        return false
    }

    mutating func scanDoubleContent(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard Self.isNbDoubleChar(lexer.lookahead) else { return false }
        if curCol == 0 && scanDocumentEnd(&lexer) {
            mrkEnd(&lexer)
            return emit(curChr == c("-") ? .s_drs_end : .s_doc_end, &lexer)
        } else {
            adv(&lexer)
        }
        while Self.isNbDoubleChar(lexer.lookahead) { adv(&lexer) }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }

    mutating func scanSingleContent(_ lexer: inout some ScannerLexer, _ symbol: TokenType) -> Bool {
        guard Self.isNbSingleChar(lexer.lookahead) else { return false }
        if curCol == 0 && scanDocumentEnd(&lexer) {
            mrkEnd(&lexer)
            return emit(curChr == c("-") ? .s_drs_end : .s_doc_end, &lexer)
        } else {
            adv(&lexer)
        }
        while Self.isNbSingleChar(lexer.lookahead) { adv(&lexer) }
        mrkEnd(&lexer)
        return emit(symbol, &lexer)
    }
}
