// Port of tree-sitter-grammars/tree-sitter-yaml/src/scanner.c and src/schema.core.c,
// commit 7708026449bed86239b1cd5bce6e3c34dbca6415 (v0.7.2).
// Copyright (c) 2024 tree-sitter-grammars contributors
// Copyright (c) 2019-2021 Ika
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public import AtelierParser

/// The stateful external scanner for the bundled YAML grammar.
public struct YAMLExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case end_of_file
        case s_dir_yml_bgn
        case r_dir_yml_ver
        case s_dir_tag_bgn
        case r_dir_tag_hdl
        case r_dir_tag_pfx
        case s_dir_rsv_bgn
        case r_dir_rsv_prm
        case s_drs_end
        case s_doc_end
        case r_blk_seq_bgn
        case br_blk_seq_bgn
        case b_blk_seq_bgn
        case r_blk_key_bgn
        case br_blk_key_bgn
        case b_blk_key_bgn
        case r_blk_val_bgn
        case br_blk_val_bgn
        case b_blk_val_bgn
        case r_blk_imp_bgn
        case r_blk_lit_bgn
        case br_blk_lit_bgn
        case r_blk_fld_bgn
        case br_blk_fld_bgn
        case br_blk_str_ctn
        case r_flw_seq_bgn
        case br_flw_seq_bgn
        case b_flw_seq_bgn
        case r_flw_seq_end
        case br_flw_seq_end
        case b_flw_seq_end
        case r_flw_map_bgn
        case br_flw_map_bgn
        case b_flw_map_bgn
        case r_flw_map_end
        case br_flw_map_end
        case b_flw_map_end
        case r_flw_sep_bgn
        case br_flw_sep_bgn
        case r_flw_key_bgn
        case br_flw_key_bgn
        case r_flw_jsv_bgn
        case br_flw_jsv_bgn
        case r_flw_njv_bgn
        case br_flw_njv_bgn
        case r_dqt_str_bgn
        case br_dqt_str_bgn
        case b_dqt_str_bgn
        case r_dqt_str_ctn
        case br_dqt_str_ctn
        case r_dqt_esc_nwl
        case br_dqt_esc_nwl
        case r_dqt_esc_seq
        case br_dqt_esc_seq
        case r_dqt_str_end
        case br_dqt_str_end
        case r_sqt_str_bgn
        case br_sqt_str_bgn
        case b_sqt_str_bgn
        case r_sqt_str_ctn
        case br_sqt_str_ctn
        case r_sqt_esc_sqt
        case br_sqt_esc_sqt
        case r_sqt_str_end
        case br_sqt_str_end
        case r_sgl_pln_nul_blk
        case br_sgl_pln_nul_blk
        case b_sgl_pln_nul_blk
        case r_sgl_pln_nul_flw
        case br_sgl_pln_nul_flw
        case r_sgl_pln_bol_blk
        case br_sgl_pln_bol_blk
        case b_sgl_pln_bol_blk
        case r_sgl_pln_bol_flw
        case br_sgl_pln_bol_flw
        case r_sgl_pln_int_blk
        case br_sgl_pln_int_blk
        case b_sgl_pln_int_blk
        case r_sgl_pln_int_flw
        case br_sgl_pln_int_flw
        case r_sgl_pln_flt_blk
        case br_sgl_pln_flt_blk
        case b_sgl_pln_flt_blk
        case r_sgl_pln_flt_flw
        case br_sgl_pln_flt_flw
        case r_sgl_pln_tms_blk
        case br_sgl_pln_tms_blk
        case b_sgl_pln_tms_blk
        case r_sgl_pln_tms_flw
        case br_sgl_pln_tms_flw
        case r_sgl_pln_str_blk
        case br_sgl_pln_str_blk
        case b_sgl_pln_str_blk
        case r_sgl_pln_str_flw
        case br_sgl_pln_str_flw
        case r_mtl_pln_str_blk
        case br_mtl_pln_str_blk
        case r_mtl_pln_str_flw
        case br_mtl_pln_str_flw
        case r_tag
        case br_tag
        case b_tag
        case r_acr_bgn
        case br_acr_bgn
        case b_acr_bgn
        case r_acr_ctn
        case r_als_bgn
        case br_als_bgn
        case b_als_bgn
        case r_als_ctn
        case bl
        case comment
        case err_rec
    }

    /// The bundled grammar’s external symbols in parser order.
    public static let externalNames = [
        "_eof", "_s_dir_yml_bgn", "_r_dir_yml_ver", "_s_dir_tag_bgn",
        "_r_dir_tag_hdl", "_r_dir_tag_pfx", "_s_dir_rsv_bgn", "_r_dir_rsv_prm",
        "_s_drs_end", "_s_doc_end", "_r_blk_seq_bgn", "_br_blk_seq_bgn",
        "_b_blk_seq_bgn", "_r_blk_key_bgn", "_br_blk_key_bgn", "_b_blk_key_bgn",
        "_r_blk_val_bgn", "_br_blk_val_bgn", "_b_blk_val_bgn", "_r_blk_imp_bgn",
        "_r_blk_lit_bgn", "_br_blk_lit_bgn", "_r_blk_fld_bgn", "_br_blk_fld_bgn",
        "_br_blk_str_ctn", "_r_flw_seq_bgn", "_br_flw_seq_bgn", "_b_flw_seq_bgn",
        "_r_flw_seq_end", "_br_flw_seq_end", "_b_flw_seq_end", "_r_flw_map_bgn",
        "_br_flw_map_bgn", "_b_flw_map_bgn", "_r_flw_map_end", "_br_flw_map_end",
        "_b_flw_map_end", "_r_flw_sep_bgn", "_br_flw_sep_bgn", "_r_flw_key_bgn",
        "_br_flw_key_bgn", "_r_flw_jsv_bgn", "_br_flw_jsv_bgn", "_r_flw_njv_bgn",
        "_br_flw_njv_bgn", "_r_dqt_str_bgn", "_br_dqt_str_bgn", "_b_dqt_str_bgn",
        "_r_dqt_str_ctn", "_br_dqt_str_ctn", "_r_dqt_esc_nwl", "_br_dqt_esc_nwl",
        "_r_dqt_esc_seq", "_br_dqt_esc_seq", "_r_dqt_str_end", "_br_dqt_str_end",
        "_r_sqt_str_bgn", "_br_sqt_str_bgn", "_b_sqt_str_bgn", "_r_sqt_str_ctn",
        "_br_sqt_str_ctn", "_r_sqt_esc_sqt", "_br_sqt_esc_sqt", "_r_sqt_str_end",
        "_br_sqt_str_end", "_r_sgl_pln_nul_blk", "_br_sgl_pln_nul_blk", "_b_sgl_pln_nul_blk",
        "_r_sgl_pln_nul_flw", "_br_sgl_pln_nul_flw", "_r_sgl_pln_bol_blk", "_br_sgl_pln_bol_blk",
        "_b_sgl_pln_bol_blk", "_r_sgl_pln_bol_flw", "_br_sgl_pln_bol_flw", "_r_sgl_pln_int_blk",
        "_br_sgl_pln_int_blk", "_b_sgl_pln_int_blk", "_r_sgl_pln_int_flw", "_br_sgl_pln_int_flw",
        "_r_sgl_pln_flt_blk", "_br_sgl_pln_flt_blk", "_b_sgl_pln_flt_blk", "_r_sgl_pln_flt_flw",
        "_br_sgl_pln_flt_flw", "_r_sgl_pln_tms_blk", "_br_sgl_pln_tms_blk", "_b_sgl_pln_tms_blk",
        "_r_sgl_pln_tms_flw", "_br_sgl_pln_tms_flw", "_r_sgl_pln_str_blk", "_br_sgl_pln_str_blk",
        "_b_sgl_pln_str_blk", "_r_sgl_pln_str_flw", "_br_sgl_pln_str_flw", "_r_mtl_pln_str_blk",
        "_br_mtl_pln_str_blk", "_r_mtl_pln_str_flw", "_br_mtl_pln_str_flw", "_r_tag",
        "_br_tag", "_b_tag", "_r_acr_bgn", "_br_acr_bgn",
        "_b_acr_bgn", "_r_acr_ctn", "_r_als_bgn", "_br_als_bgn",
        "_b_als_bgn", "_r_als_ctn", "_bl", "comment",
        "_err_rec"
    ]

    enum ResultSchema { case string, integer, null, boolean, float }

    static let indRot: UInt32 = 114
    static let indMap: UInt32 = 109
    static let indSeq: UInt32 = 113
    static let indStr: UInt32 = 115
    static let scanSuccess = 1
    static let scanStop = 0
    static let scanFailure = -1

    var row = 0
    var col = 0
    var blkImpRow = -1
    var blkImpCol = -1
    var blkImpTab = false
    var indTypStack: [UInt32] = [indRot]
    var indLenStack: [Int] = [-1]

    // Temporary fields match Scanner's temporary C fields.
    var endRow = 0
    var endCol = 0
    var curRow = 0
    var curCol = 0
    var curChr: UInt32 = 0
    var schStt = 0
    var rltSch: ResultSchema = .string
    var stateOverflow = false
    var didEmit = false

    /// Creates the root indentation state.
    public init() {}

    /// Appends the C scanner’s little endian state, capped by the parser’s state buffer.
    /// - Complexity: O(d), where d is the indentation stack depth.
    public func serialize(into buffer: inout [UInt8]) {
        guard !stateOverflow else { return }
        let count = min(indTypStack.count, indLenStack.count)
        let encoded = min(count - 1, (maximumSerializedScannerStateSize - 10) / 4)
        buffer.reserveCapacity(buffer.count + 10 + encoded * 4)
        Self.appendInt16(row, to: &buffer)
        Self.appendInt16(col, to: &buffer)
        Self.appendInt16(blkImpRow, to: &buffer)
        Self.appendInt16(blkImpCol, to: &buffer)
        Self.appendInt16(blkImpTab ? 1 : 0, to: &buffer)
        if encoded > 0 {
            for index in 1 ... encoded {
                Self.appendInt16(Int(indTypStack[index]), to: &buffer)
                Self.appendInt16(indLenStack[index], to: &buffer)
            }
        }
    }

    /// Restores a C scanner state; empty or malformed data resets it to the root state.
    /// - Complexity: O(n), where n is the number of state bytes.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        self = Self()
        guard !state.isEmpty else { return }
        guard state.count >= 10, state.count <= maximumSerializedScannerStateSize,
            (state.count - 10) % 4 == 0
        else { return }
        var index = state.startIndex
        func readInt16() -> Int {
            let low = UInt16(state[index])
            index = state.index(after: index)
            let high = UInt16(state[index])
            index = state.index(after: index)
            return Int(Int16(bitPattern: low | high << 8))
        }
        row = readInt16()
        col = readInt16()
        blkImpRow = readInt16()
        blkImpCol = readInt16()
        blkImpTab = readInt16() != 0
        while index < state.endIndex {
            let type = readInt16()
            let length = readInt16()
            guard type >= 0, length >= -1 else {
                self = Self()
                return
            }
            indTypStack.append(UInt32(type))
            indLenStack.append(length)
        }
    }

    /// Scans one offered token and commits state only when the token is offered.
    /// - Returns: Whether an offered token was recognized.
    /// - Complexity: O(n), where n is the number of examined input scalars.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        var trial = self
        guard trial.scanUnchecked(&lexer, validSymbols: validSymbols),
            trial.didEmit, validSymbols.indices.contains(lexer.resultSymbol),
            validSymbols[lexer.resultSymbol], !trial.stateOverflow
        else { return false }
        self = trial
        return true
    }

    static func appendInt16(_ value: Int, to buffer: inout [UInt8]) {
        let bits = UInt16(bitPattern: Int16(truncatingIfNeeded: value))
        buffer.append(UInt8(truncatingIfNeeded: bits))
        buffer.append(UInt8(truncatingIfNeeded: bits >> 8))
    }

    mutating func adv(_ lexer: inout some ScannerLexer) {
        curCol += 1
        curChr = lexer.lookahead
        lexer.advance(skip: false)
    }

    mutating func advNwl(_ lexer: inout some ScannerLexer) {
        curRow += 1
        curCol = 0
        curChr = lexer.lookahead
        lexer.advance(skip: false)
    }

    mutating func skp(_ lexer: inout some ScannerLexer) {
        curCol += 1
        curChr = lexer.lookahead
        lexer.advance(skip: true)
    }

    mutating func skpNwl(_ lexer: inout some ScannerLexer) {
        curRow += 1
        curCol = 0
        curChr = lexer.lookahead
        lexer.advance(skip: true)
    }

    mutating func mrkEnd(_ lexer: inout some ScannerLexer) {
        endRow = curRow
        endCol = curCol
        lexer.markEnd()
    }

    mutating func initScan() {
        didEmit = false
        curRow = row
        curCol = col
        curChr = 0
        schStt = 0
        rltSch = .string
    }

    mutating func emit(_ symbol: TokenType, _ lexer: inout some ScannerLexer) -> Bool {
        guard !stateOverflow else { return false }
        row = endRow
        col = endCol
        didEmit = true
        lexer.resultSymbol = symbol.rawValue
        return true
    }

    mutating func popInd() -> Bool {
        // Incorrect status may be caused by error recovery.
        guard indTypStack.count > 1 else { return false }
        indTypStack.removeLast()
        indLenStack.removeLast()
        return true
    }

    mutating func pushInd(_ type: UInt32, _ length: Int) {
        guard indTypStack.count < 254 else {
            stateOverflow = true
            return
        }
        indTypStack.append(type)
        indLenStack.append(length)
    }

    mutating func mayUpdateImplicitColumn(row beginningRow: Int, col beginningCol: Int, hasTab: Bool) {
        if blkImpRow != beginningRow {
            blkImpRow = beginningRow
            blkImpCol = beginningCol
            blkImpTab = hasTab
        }
    }
}
