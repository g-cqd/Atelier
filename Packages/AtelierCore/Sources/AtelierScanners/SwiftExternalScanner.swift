// Port of alex-pinkus/tree-sitter-swift/src/scanner.c, tag 0.7.3,
// commit b8b22bffbb3441780e6471665bacfb263741c86a.
// MIT License
// Copyright (c) 2021 alex-pinkus
//
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

/// The external scanner for the pinned tree-sitter Swift grammar.
///
/// The value holds the number of hashes in a raw string across interpolation boundaries.
public struct SwiftExternalScanner: GrammarExternalScanner {
    enum TokenType: Int {
        case blockComment
        case rawStrPart
        case rawStrContinuingIndicator
        case rawStrEndPart
        case implicitSemi
        case explicitSemi
        case arrowOperator
        case dotOperator
        case conjunctionOperator
        case disjunctionOperator
        case nilCoalescingOperator
        case equalSign
        case eqEq
        case plusThenWS
        case minusThenWS
        case bang
        case throwsKeyword
        case rethrowsKeyword
        case defaultKeyword
        case whereKeyword
        case elseKeyword
        case catchKeyword
        case asKeyword
        case asQuest
        case asBang
        case asyncKeyword
        case customOperator
        case hashSymbol
        case directiveIf
        case directiveElseif
        case directiveElse
        case directiveEndif
        case fakeTryBang
    }

    /// All possible results of having performed some sort of parsing.
    ///
    /// A parser can return a result along two dimensions:
    /// 1. Should the scanner continue trying to find another result?
    /// 2. Was some result produced by this parsing attempt?
    ///
    /// These are flattened into a single enum together. When a function returns a token case, it populates its
    /// `symbolResult` out parameter. When it returns a stop case, callers return immediately.
    enum ParseDirective {
        case continueNothing
        case continueToken
        case continueSlashConsumed
        case stopNothing
        case stopToken
        case stopEndOfFile
    }

    /// The `externals` of upstream `src/grammar.json`, in grammar order.
    public static let externalNames = [
        "multiline_comment", "raw_str_part", "raw_str_continuing_indicator", "raw_str_end_part",
        "_implicit_semi", "_explicit_semi", "_arrow_operator_custom", "_dot_custom",
        "_conjunction_operator_custom", "_disjunction_operator_custom", "_nil_coalescing_operator_custom",
        "_eq_custom", "_eq_eq_custom", "_plus_then_ws", "_minus_then_ws", "_bang_custom",
        "_throws_keyword", "_rethrows_keyword", "default_keyword", "where_keyword", "else",
        "catch_keyword", "_as_custom", "_as_quest_custom", "_as_bang_custom", "_async_keyword_custom",
        "_custom_operator", "_hash_symbol_custom", "_directive_if", "_directive_elseif", "_directive_else",
        "_directive_endif", "_fake_try_bang"
    ]

    static let nonConsumingCrossSemiChars = [ascii("?"), ascii(":"), ascii("{")]

    var ongoingRawStringHashCount: UInt32 = 0

    /// Creates a scanner outside a raw string.
    public init() {}

    /// Appends the raw string hash count as four big endian bytes.
    public func serialize(into buffer: inout [UInt8]) {
        let count = ongoingRawStringHashCount
        buffer.append(UInt8(truncatingIfNeeded: count >> 24))
        buffer.append(UInt8(truncatingIfNeeded: count >> 16))
        buffer.append(UInt8(truncatingIfNeeded: count >> 8))
        buffer.append(UInt8(truncatingIfNeeded: count))
    }

    /// Restores the hash count; an empty state resets it.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        if state.isEmpty {
            ongoingRawStringHashCount = 0
            return
        }
        guard state.count >= 4 else { return }
        var bytes = state.startIndex
        let first = UInt32(state[bytes])
        state.formIndex(after: &bytes)
        let second = UInt32(state[bytes])
        state.formIndex(after: &bytes)
        let third = UInt32(state[bytes])
        state.formIndex(after: &bytes)
        let fourth = UInt32(state[bytes])
        ongoingRawStringHashCount = first << 24 | second << 16 | third << 8 | fourth
    }

    /// Scans one external token, with the same branch order as the upstream C scanner.
    /// - Returns: Whether an offered token was found.
    /// - Complexity: O(n), where n is the number of input scalars examined.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }

        // Consume any whitespace at the start.
        var whitespaceResult: TokenType?
        let whitespace = Self.eatWhitespace(&lexer, validSymbols: validSymbols, symbolResult: &whitespaceResult)
        if whitespace == .stopToken {
            return Self.emit(whitespaceResult, lexer: &lexer, validSymbols: validSymbols)
        }
        if whitespace == .stopNothing || whitespace == .stopEndOfFile { return false }
        let hasWhitespaceResult = whitespace == .continueToken

        // Now consume comments (before custom operators so that those aren't treated as comments)
        var commentResult: TokenType?
        let comment =
            whitespace == .continueSlashConsumed
            ? whitespace : Self.eatComment(&lexer, markEnd: true, symbolResult: &commentResult)
        if comment == .stopToken {
            lexer.markEnd()
            return Self.emit(commentResult, lexer: &lexer, validSymbols: validSymbols)
        }
        if comment == .stopEndOfFile { return false }

        // Now consume any operators that might cause our whitespace to be suppressed.
        var operatorResult: TokenType?
        let sawOperator = Self.eatOperators(
            &lexer, validSymbols: validSymbols, markEnd: !hasWhitespaceResult,
            priorChar: comment == .continueSlashConsumed ? Self.ascii("/") : 0,
            symbolResult: &operatorResult
        )
        if sawOperator, let operatorResult, !hasWhitespaceResult || Self.isCrossSemiToken(operatorResult) {
            if hasWhitespaceResult { lexer.markEnd() }
            return Self.emit(operatorResult, lexer: &lexer, validSymbols: validSymbols)
        }
        if hasWhitespaceResult {
            // Don't `mark_end`, since we may have advanced through some operators.
            return Self.emit(whitespaceResult, lexer: &lexer, validSymbols: validSymbols)
        }

        // NOTE: this will consume any `#` characters it sees, even if it does not find a result. Keep
        // it at the end so that it doesn't interfere with special literals or selectors!
        var trial = self
        var rawStringResult: TokenType?
        if trial.eatRawStringPart(&lexer, validSymbols: validSymbols, symbolResult: &rawStringResult),
            let rawStringResult,
            validSymbols[rawStringResult.rawValue]
        {
            self = trial
            lexer.resultSymbol = rawStringResult.rawValue
            return true
        }
        return false
    }

    static func emit(
        _ token: TokenType?, lexer: inout some ScannerLexer, validSymbols: [Bool]
    ) -> Bool {
        guard let token, validSymbols[token.rawValue] else { return false }
        lexer.resultSymbol = token.rawValue
        return true
    }

    static func ascii(_ character: Unicode.Scalar) -> UInt32 { UInt32(UInt8(ascii: character)) }

    static func isWhitespace(_ scalar: UInt32) -> Bool {
        guard let unicode = Unicode.Scalar(scalar) else { return false }
        return unicode.properties.isWhitespace
    }

    static func isAlphanumeric(_ scalar: UInt32) -> Bool {
        guard let unicode = Unicode.Scalar(scalar) else { return false }
        return unicode.properties.isAlphabetic || unicode.properties.numericType != nil
    }

    static func shouldTreatAsWhitespace(_ scalar: UInt32) -> Bool {
        isWhitespace(scalar) || scalar == ascii(";")
    }

    static func isCrossSemiToken(_ token: TokenType) -> Bool {
        switch token {
            case .arrowOperator, .dotOperator, .conjunctionOperator, .disjunctionOperator,
                .nilCoalescingOperator, .equalSign, .eqEq, .plusThenWS, .minusThenWS,
                .throwsKeyword, .rethrowsKeyword, .defaultKeyword, .whereKeyword, .elseKeyword,
                .catchKeyword, .asKeyword, .asQuest, .asBang, .asyncKeyword, .customOperator:
                true
            default:
                false
        }
    }

    static func eatComment(
        _ lexer: inout some ScannerLexer, markEnd: Bool, symbolResult: inout TokenType?
    ) -> ParseDirective {
        guard lexer.lookahead == ascii("/") else { return .continueNothing }
        lexer.advance(skip: false)
        guard lexer.lookahead == ascii("*") else { return .continueSlashConsumed }
        lexer.advance(skip: false)

        var afterStar = false
        var nestingDepth = 1
        while true {
            switch lexer.lookahead {
                case 0:
                    return .stopEndOfFile
                case ascii("*"):
                    lexer.advance(skip: false)
                    afterStar = true
                case ascii("/"):
                    if afterStar {
                        lexer.advance(skip: false)
                        afterStar = false
                        nestingDepth -= 1
                        if nestingDepth == 0 {
                            if markEnd { lexer.markEnd() }
                            symbolResult = .blockComment
                            return .stopToken
                        }
                    } else {
                        lexer.advance(skip: false)
                        afterStar = false
                        if lexer.lookahead == ascii("*") {
                            nestingDepth += 1
                            lexer.advance(skip: false)
                        }
                    }
                default:
                    lexer.advance(skip: false)
                    afterStar = false
            }
        }
    }

    // Preserve the pinned scanner's newline, comment and operator decision order.
    // swiftlint:disable:next cyclomatic_complexity
    static func eatWhitespace(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], symbolResult: inout TokenType?
    ) -> ParseDirective {
        var whitespaceDirective: ParseDirective = .continueNothing
        let semiIsValid = validSymbols[TokenType.implicitSemi.rawValue] && validSymbols[TokenType.explicitSemi.rawValue]
        var lookahead = lexer.lookahead
        while shouldTreatAsWhitespace(lookahead) {
            if lookahead == ascii(";") {
                if semiIsValid {
                    whitespaceDirective = .stopToken
                    lexer.advance(skip: false)
                }
                break
            }
            lexer.advance(skip: true)
            lexer.markEnd()
            if whitespaceDirective == .continueNothing && (lookahead == ascii("\n") || lookahead == ascii("\r")) {
                whitespaceDirective = .continueToken
            }
            lookahead = lexer.lookahead
        }

        var anyComment: ParseDirective = .continueNothing
        if whitespaceDirective == .continueToken && lookahead == ascii("/") {
            var hasSeenSingleComment = false
            while lexer.lookahead == ascii("/") {
                // It's possible that this is a comment - start an exploratory mission to find out, and if it is, look
                // for what comes after it. We care about what comes after it for the purpose of suppressing the newline.
                var multilineCommentResult: TokenType?
                anyComment = eatComment(&lexer, markEnd: false, symbolResult: &multilineCommentResult)
                if anyComment == .stopToken {
                    // This is a multiline comment. This scanner should be parsing those, so we might want to bail out
                    // and emit it instead. However, we only want to do that if we haven't advanced through a _single_
                    // line comment on the way - otherwise that will get lumped into this.
                    if !hasSeenSingleComment {
                        lexer.markEnd()
                        symbolResult = multilineCommentResult
                        return .stopToken
                    }
                } else if anyComment == .stopEndOfFile {
                    return .stopEndOfFile
                } else if anyComment == .continueSlashConsumed {
                    // We accidentally ate a slash -- we should actually bail out, say we saw nothing, and let the next
                    // pass take it from after the newline.
                    return .continueSlashConsumed
                } else if lexer.lookahead == ascii("/") {
                    // There wasn't a multiline comment, which we know means that the comment parser ate its `/` and
                    // then bailed out. If it had seen anything comment-like after that first `/` it would have
                    // continued going and eventually had a well-formed comment or an EOF. Thus, if we're currently
                    // looking at a `/`, it's the second one of those and it means we have a single-line comment.
                    hasSeenSingleComment = true
                    while lexer.lookahead != ascii("\n") && lexer.lookahead != 0 {
                        lexer.advance(skip: true)
                    }
                } else if isWhitespace(lexer.lookahead) {
                    // We didn't see any type of comment - in fact, we saw an operator that we don't normally treat as
                    // an operator. Still, this is a reason to stop parsing.
                    return .stopNothing
                }
                while isWhitespace(lexer.lookahead) {
                    anyComment = .continueNothing
                    lexer.advance(skip: true)
                }
            }

            var operatorResult: TokenType?
            let sawOperator = eatOperators(
                &lexer, validSymbols: validSymbols, markEnd: false, priorChar: 0, symbolResult: &operatorResult
            )
            if sawOperator {
                // The operator we saw should suppress the newline, so bail out.
                return .stopNothing
            } else {
                // Promote the implicit newline to an explicit one so we don't check for operators again.
                symbolResult = .implicitSemi
                whitespaceDirective = .stopToken
            }
        }

        // Let's consume operators that can live after a "semicolon" style newline. Before we do that, though, we want
        // to check for a set of characters that we do not consume, but that still suppress the semi.
        if whitespaceDirective == .continueToken {
            for character in nonConsumingCrossSemiChars where character == lookahead {
                return .continueNothing
            }
        }
        if semiIsValid && whitespaceDirective != .continueNothing {
            symbolResult = lookahead == ascii(";") ? .explicitSemi : .implicitSemi
            return whitespaceDirective
        }
        return .continueNothing
    }
}
