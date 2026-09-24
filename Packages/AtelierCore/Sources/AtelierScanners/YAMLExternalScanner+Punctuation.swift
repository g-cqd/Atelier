import AtelierParser

private func c(_ value: Unicode.Scalar) -> UInt32 { value.value }

extension YAMLExternalScanner {
    // Preserve the C scanner's precedence among offered punctuation symbols.
    // swiftlint:disable:next cyclomatic_complexity function_body_length function_parameter_count
    mutating func scanPunctuation(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], isR: Bool, isBr: Bool, isB: Bool, isS: Bool,
        beginningRow: Int, beginningCol: Int, currentIndent: Int, currentIndentType: UInt32, hasTabIndent: Bool
    ) -> Bool? {
        func has(_ symbol: TokenType) -> Bool { validSymbols[symbol.rawValue] }
        func offered(_ r: TokenType, _ br: TokenType, _ b: TokenType? = nil) -> TokenType? {
            if has(r) && isR { return r }
            if has(br) && isBr { return br }
            if let b, has(b) && isB { return b }
            return nil
        }
        if lexer.lookahead == c("%") {
            if has(.s_dir_yml_bgn) && isS { return scanDirectiveBeginning(&lexer) }
        } else if lexer.lookahead == c("*") {
            if let symbol = offered(.r_als_bgn, .br_als_bgn, .b_als_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                return scanAliasBeginning(&lexer, symbol)
            }
        } else if lexer.lookahead == c("&") {
            if let symbol = offered(.r_acr_bgn, .br_acr_bgn, .b_acr_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                return scanAnchorBeginning(&lexer, symbol)
            }
        } else if lexer.lookahead == c("!") {
            if let symbol = offered(.r_tag, .br_tag, .b_tag) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                return scanTag(&lexer, symbol)
            }
        } else if lexer.lookahead == c("[") {
            if let symbol = offered(.r_flw_seq_bgn, .br_flw_seq_bgn, .b_flw_seq_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        } else if lexer.lookahead == c("]") {
            if let symbol = offered(.r_flw_seq_end, .br_flw_seq_end, .b_flw_seq_end) {
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol == .b_flw_seq_end ? .br_flw_seq_end : symbol, &lexer)
            }
        } else if lexer.lookahead == c("{") {
            if let symbol = offered(.r_flw_map_bgn, .br_flw_map_bgn, .b_flw_map_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        } else if lexer.lookahead == c("}") {
            if let symbol = offered(.r_flw_map_end, .br_flw_map_end, .b_flw_map_end) {
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol == .b_flw_map_end ? .br_flw_map_end : symbol, &lexer)
            }
        } else if lexer.lookahead == c(",") {
            if let symbol = offered(.r_flw_sep_bgn, .br_flw_sep_bgn) {
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        } else if lexer.lookahead == c("\"") {
            if let symbol = offered(.r_dqt_str_bgn, .br_dqt_str_bgn, .b_dqt_str_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
            if let symbol = offered(.r_dqt_str_end, .br_dqt_str_end) {
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        } else if lexer.lookahead == c("'") {
            if let symbol = offered(.r_sqt_str_bgn, .br_sqt_str_bgn, .b_sqt_str_bgn) {
                mayUpdateImplicitColumn(row: beginningRow, col: beginningCol, hasTab: hasTabIndent)
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
            if let symbol = offered(.r_sqt_str_end, .br_sqt_str_end) {
                adv(&lexer)
                if lexer.lookahead == c("'") {
                    adv(&lexer)
                    mrkEnd(&lexer)
                    return emit(symbol == .r_sqt_str_end ? .r_sqt_esc_sqt : .br_sqt_esc_sqt, &lexer)
                }
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
        } else if lexer.lookahead == c("?") {
            let blockR = has(.r_blk_key_bgn) && isR
            let blockBr = has(.br_blk_key_bgn) && isBr
            let blockB = has(.b_blk_key_bgn) && isB
            let flowR = has(.r_flw_key_bgn) && isR
            let flowBr = has(.br_flw_key_bgn) && isBr
            if blockR || blockBr || blockB || flowR || flowBr {
                adv(&lexer)
                if Self.isWht(lexer.lookahead) {
                    mrkEnd(&lexer)
                    if blockR || blockBr {
                        guard !hasTabIndent else { return false }
                        pushInd(Self.indMap, beginningCol)
                        return emit(blockR ? .r_blk_key_bgn : .br_blk_key_bgn, &lexer)
                    }
                    if blockB { return emit(.b_blk_key_bgn, &lexer) }
                    if flowR { return emit(.r_flw_key_bgn, &lexer) }
                    if flowBr { return emit(.br_flw_key_bgn, &lexer) }
                }
            }
        } else if lexer.lookahead == c(":") {
            if let symbol = offered(.r_flw_jsv_bgn, .br_flw_jsv_bgn) {
                adv(&lexer)
                mrkEnd(&lexer)
                return emit(symbol, &lexer)
            }
            let blockR = has(.r_blk_val_bgn) && isR
            let blockBr = has(.br_blk_val_bgn) && isBr
            let blockB = has(.b_blk_val_bgn) && isB
            let implicitR = has(.r_blk_imp_bgn) && isR
            let flowR = has(.r_flw_njv_bgn) && isR
            let flowBr = has(.br_flw_njv_bgn) && isBr
            if blockR || blockBr || blockB || implicitR || flowR || flowBr {
                adv(&lexer)
                let whitespace = Self.isWht(lexer.lookahead)
                if whitespace {
                    if blockR || blockBr {
                        guard !hasTabIndent else { return false }
                        pushInd(Self.indMap, beginningCol)
                        mrkEnd(&lexer)
                        return emit(blockR ? .r_blk_val_bgn : .br_blk_val_bgn, &lexer)
                    }
                    if blockB {
                        mrkEnd(&lexer)
                        return emit(.b_blk_val_bgn, &lexer)
                    }
                    if implicitR {
                        if currentIndent != blkImpCol {
                            guard !blkImpTab else { return false }
                            pushInd(Self.indMap, blkImpCol)
                        }
                        mrkEnd(&lexer)
                        return emit(.r_blk_imp_bgn, &lexer)
                    }
                }
                if whitespace || lexer.lookahead == c(",") || lexer.lookahead == c("]")
                    || lexer.lookahead == c("}")
                {
                    if flowR {
                        mrkEnd(&lexer)
                        return emit(.r_flw_njv_bgn, &lexer)
                    }
                    if flowBr {
                        mrkEnd(&lexer)
                        return emit(.br_flw_njv_bgn, &lexer)
                    }
                }
            }
        } else if lexer.lookahead == c("-") {
            let blockR = has(.r_blk_seq_bgn) && isR
            let blockBr = has(.br_blk_seq_bgn) && isBr
            let blockB = has(.b_blk_seq_bgn) && isB
            if blockR || blockBr || blockB || isS {
                adv(&lexer)
                if Self.isWht(lexer.lookahead) {
                    if blockR || blockBr {
                        guard !hasTabIndent else { return false }
                        pushInd(Self.indSeq, beginningCol)
                        mrkEnd(&lexer)
                        return emit(blockR ? .r_blk_seq_bgn : .br_blk_seq_bgn, &lexer)
                    }
                    if blockB {
                        if currentIndentType == Self.indMap { pushInd(Self.indSeq, beginningCol) }
                        mrkEnd(&lexer)
                        return emit(.b_blk_seq_bgn, &lexer)
                    }
                } else if lexer.lookahead == c("-") && isS {
                    adv(&lexer)
                    if lexer.lookahead == c("-") {
                        adv(&lexer)
                        if Self.isWht(lexer.lookahead) {
                            if has(.bl) {
                                guard popInd() else { return false }
                                return emit(.bl, &lexer)
                            }
                            mrkEnd(&lexer)
                            return emit(.s_drs_end, &lexer)
                        }
                    }
                }
            }
        } else if lexer.lookahead == c(".") {
            if isS {
                adv(&lexer)
                if lexer.lookahead == c(".") {
                    adv(&lexer)
                    if lexer.lookahead == c(".") {
                        adv(&lexer)
                        if Self.isWht(lexer.lookahead) {
                            if has(.bl) {
                                guard popInd() else { return false }
                                return emit(.bl, &lexer)
                            }
                            mrkEnd(&lexer)
                            return emit(.s_doc_end, &lexer)
                        }
                    }
                }
            }
        } else if lexer.lookahead == c("\\") {
            let newline = offered(.r_dqt_esc_nwl, .br_dqt_esc_nwl)
            let sequence = offered(.r_dqt_esc_seq, .br_dqt_esc_seq)
            if newline != nil || sequence != nil {
                adv(&lexer)
                if Self.isNwl(lexer.lookahead), let newline {
                    mrkEnd(&lexer)
                    return emit(newline, &lexer)
                }
                if let sequence { return scanDoubleEscape(&lexer, sequence) }
                return false
            }
        } else if lexer.lookahead == c("|") {
            if let symbol = offered(.r_blk_lit_bgn, .br_blk_lit_bgn) {
                return scanBlockStringBeginning(&lexer, symbol)
            }
        } else if lexer.lookahead == c(">") {
            if let symbol = offered(.r_blk_fld_bgn, .br_blk_fld_bgn) {
                return scanBlockStringBeginning(&lexer, symbol)
            }
        }
        return nil
    }
}
