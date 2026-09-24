import AtelierParser

private func c(_ value: Unicode.Scalar) -> UInt32 { value.value }

extension YAMLExternalScanner {
    // The C scanner's token order decides ambiguous YAML input.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func scanUnchecked(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        func has(_ symbol: TokenType) -> Bool { validSymbols[symbol.rawValue] }
        initScan()
        mrkEnd(&lexer)

        let allowComment =
            !(has(.r_dqt_str_ctn) || has(.br_dqt_str_ctn)
            || has(.r_sqt_str_ctn) || has(.br_sqt_str_ctn))
        let currentIndent = indLenStack[indLenStack.count - 1]
        let parentIndent = indLenStack.count == 1 ? -1 : indLenStack[indLenStack.count - 2]
        let currentIndentType = indTypStack[indTypStack.count - 1]
        var hasTabIndent = false
        var leadingSpaces = 0

        while true {
            if lexer.lookahead == c(" ") {
                if !hasTabIndent { leadingSpaces += 1 }
                skp(&lexer)
            } else if lexer.lookahead == c("\t") {
                hasTabIndent = true
                skp(&lexer)
            } else if Self.isNwl(lexer.lookahead) {
                hasTabIndent = false
                leadingSpaces = 0
                skpNwl(&lexer)
            } else if allowComment && lexer.lookahead == c("#") {
                if has(.br_blk_str_ctn) && has(.bl) && curCol <= currentIndent {
                    guard popInd() else { return false }
                    return emit(.bl, &lexer)
                }
                guard has(.br_blk_str_ctn) ? curRow == row : curCol == 0 || curRow != row || curCol > col else { break }
                adv(&lexer)
                while !Self.isNwl(lexer.lookahead) && lexer.lookahead != 0 { adv(&lexer) }
                mrkEnd(&lexer)
                return emit(.comment, &lexer)
            } else {
                break
            }
        }

        if lexer.lookahead == 0 {
            if has(.bl) {
                mrkEnd(&lexer)
                guard popInd() else { return false }
                return emit(.bl, &lexer)
            }
            if has(.end_of_file) {
                mrkEnd(&lexer)
                return emit(.end_of_file, &lexer)
            }
            return false
        }

        let beginningRow = curRow
        let beginningCol = curCol
        let beginningChar = lexer.lookahead

        if has(.bl) && beginningCol <= currentIndent && !hasTabIndent {
            let mustPop =
                currentIndent == parentIndent && currentIndentType == Self.indSeq
                ? beginningCol < currentIndent || lexer.lookahead != c("-")
                : beginningCol <= parentIndent || currentIndentType == Self.indStr
            if mustPop {
                guard popInd() else { return false }
                return emit(.bl, &lexer)
            }
        }

        let hasNewline = curRow > row
        let isR = !hasNewline
        let isBr = hasNewline && leadingSpaces > currentIndent
        let isB = hasNewline && leadingSpaces == currentIndent && !hasTabIndent
        let isS = beginningCol == 0

        if has(.r_dir_yml_ver) && isR { return scanDirectiveVersion(&lexer, .r_dir_yml_ver) }
        if has(.r_dir_tag_hdl) && isR { return scanDirectiveTagHandle(&lexer, .r_dir_tag_hdl) }
        if has(.r_dir_tag_pfx) && isR { return scanDirectiveTagPrefix(&lexer, .r_dir_tag_pfx) }
        if has(.r_dir_rsv_prm) && isR { return scanDirectiveReservedParameter(&lexer, .r_dir_rsv_prm) }
        if has(.br_blk_str_ctn) && isBr && scanBlockStringContent(&lexer, .br_blk_str_ctn) { return true }
        if has(.r_dqt_str_ctn) && isR && scanDoubleContent(&lexer, .r_dqt_str_ctn) { return true }
        if has(.br_dqt_str_ctn) && isBr && scanDoubleContent(&lexer, .br_dqt_str_ctn) { return true }
        if has(.r_sqt_str_ctn) && isR && scanSingleContent(&lexer, .r_sqt_str_ctn) { return true }
        if has(.br_sqt_str_ctn) && isBr && scanSingleContent(&lexer, .br_sqt_str_ctn) { return true }
        if has(.r_acr_ctn) && isR { return scanAnchorContent(&lexer, .r_acr_ctn) }
        if has(.r_als_ctn) && isR { return scanAliasContent(&lexer, .r_als_ctn) }

        if let result = scanPunctuation(
            &lexer, validSymbols: validSymbols, isR: isR, isBr: isBr, isB: isB, isS: isS,
            beginningRow: beginningRow, beginningCol: beginningCol, currentIndent: currentIndent,
            currentIndentType: currentIndentType, hasTabIndent: hasTabIndent
        ) {
            return result
        }

        let singleBlock =
            (has(.r_sgl_pln_str_blk) && isR) || (has(.br_sgl_pln_str_blk) && isBr)
            || (has(.b_sgl_pln_str_blk) && isB)
        let singleFlow = (has(.r_sgl_pln_str_flw) && isR) || (has(.br_sgl_pln_str_flw) && isBr)
        let multiBlock = (has(.r_mtl_pln_str_blk) && isR) || (has(.br_mtl_pln_str_blk) && isBr)
        let multiFlow = (has(.r_mtl_pln_str_flw) && isR) || (has(.br_mtl_pln_str_flw) && isBr)
        if singleBlock || singleFlow || multiBlock || multiFlow {
            let inBlock = singleBlock || multiBlock
            if curCol - beginningCol == 0 { adv(&lexer) }
            if curCol - beginningCol == 1 {
                let first =
                    (Self.isNsChar(beginningChar) && !Self.isIndicator(beginningChar))
                    || ((beginningChar == c("-") || beginningChar == c("?") || beginningChar == c(":"))
                        && (inBlock ? Self.isPlainSafeBlock(lexer.lookahead) : Self.isPlainSafeFlow(lexer.lookahead)))
                guard first else { return false }
                guard advanceSchemaState() else { return false }
            } else {
                // ..X, ...X, --X, and ---X cannot be schema scalars.
                schStt = -1
            }
            mrkEnd(&lexer)
            while true {
                if !Self.isNwl(lexer.lookahead) && scanPlainContent(&lexer, inBlock: inBlock) != Self.scanSuccess {
                    break
                }
                if lexer.lookahead == 0 || !Self.isNwl(lexer.lookahead) { break }
                while true {
                    if Self.isNwl(lexer.lookahead) {
                        advNwl(&lexer)
                    } else if Self.isWsp(lexer.lookahead) {
                        adv(&lexer)
                    } else {
                        break
                    }
                }
                if lexer.lookahead == 0 || curCol <= currentIndent { break }
                if curCol == 0 && scanDocumentEnd(&lexer) { break }
            }
            if endRow == beginningRow {
                if singleBlock {
                    mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                    guard let symbol = plainSymbol(position: isR ? 0 : isBr ? 1 : 2, inBlock: true) else {
                        return false
                    }
                    return emit(symbol, &lexer)
                }
                if singleFlow {
                    guard let symbol = plainSymbol(position: isR ? 0 : 1, inBlock: false) else { return false }
                    return emit(symbol, &lexer)
                }
            } else {
                if multiBlock {
                    mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                    return emit(isR ? .r_mtl_pln_str_blk : .br_mtl_pln_str_blk, &lexer)
                }
                if multiFlow { return emit(isR ? .r_mtl_pln_str_flw : .br_mtl_pln_str_flw, &lexer) }
            }
            return false
        }
        return !has(.err_rec)
    }
}
