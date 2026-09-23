import AtelierParser

extension SwiftExternalScanner {
    enum IllegalTerminatorGroup {
        case alphanumeric
        case operatorSymbols
        case operatorOrDot
        case nonWhitespace
    }

    static let operators: [[UInt8]] = [
        "->", ".", "&&", "||", "??", "=", "==", "+", "-", "!", "throws", "rethrows", "default", "where",
        "else", "catch", "as", "as?", "as!", "async"
    ]
    .map { Array($0.utf8) }

    static let operatorIllegalTerminators: [IllegalTerminatorGroup] = [
        .operatorSymbols,  // ->
        .operatorOrDot,  // .
        .operatorSymbols,  // &&
        .operatorSymbols,  // ||
        .operatorSymbols,  // ??
        .operatorSymbols,  // =
        .operatorSymbols,  // ==
        .nonWhitespace,  // +
        .nonWhitespace,  // -
        .operatorSymbols,  // !
        .alphanumeric,  // throws
        .alphanumeric,  // rethrows
        .alphanumeric,  // default
        .alphanumeric,  // where
        .alphanumeric,  // else
        .alphanumeric,  // catch
        .alphanumeric,  // as
        .operatorSymbols,  // as?
        .operatorSymbols,  // as!
        .alphanumeric  // async
    ]

    static let operatorSymbols: [TokenType] = [
        .arrowOperator, .dotOperator, .conjunctionOperator, .disjunctionOperator, .nilCoalescingOperator,
        .equalSign, .eqEq, .plusThenWS, .minusThenWS, .bang, .throwsKeyword, .rethrowsKeyword,
        .defaultKeyword, .whereKeyword, .elseKeyword, .catchKeyword, .asKeyword, .asQuest,
        .asBang, .asyncKeyword
    ]

    static let reservedOperators: [[UInt8]] = [
        "/", "=", "-", "+", "!", "*", "%", "<", ">", "&", "|", "^", "?", "~", ".", "..", "->", "/*",
        "*/", "+=", "-=", "*=", "/=", "%=", ">>", "<<", "++", "--", "===", "...", "..<"
    ]
    .map { Array($0.utf8) }

    static func isLegalCustomOperator(_ charIndex: Int, firstChar: UInt32, currentChar: UInt32) -> Bool {
        let isFirstChar = charIndex == 0
        switch currentChar {
            case ascii("="), ascii("-"), ascii("+"), ascii("!"), ascii("%"), ascii("<"), ascii(">"),
                ascii("&"), ascii("|"), ascii("^"), ascii("?"), ascii("~"):
                return true
            case ascii("."):
                // Grammar allows `.` for any operator that starts with `.`
                return isFirstChar || firstChar == ascii(".")
            case ascii("*"), ascii("/"):
                // Not listed in the grammar, but `/*` and `//` can't be the start of an operator since they start comments
                return charIndex != 1 || firstChar != ascii("/")
            default:
                if (0x00A1 ... 0x00A7).contains(currentChar)
                    || currentChar == 0x00A9 || currentChar == 0x00AB || currentChar == 0x00AC
                    || (0x00B0 ... 0x00B1).contains(currentChar) || currentChar == 0x00B6
                    || currentChar == 0x00BB || currentChar == 0x00BF || currentChar == 0x00D7
                    || currentChar == 0x00F7 || (0x2016 ... 0x2017).contains(currentChar)
                    || (0x2020 ... 0x2027).contains(currentChar) || (0x2030 ... 0x203E).contains(currentChar)
                    || (0x2041 ... 0x2053).contains(currentChar) || (0x2055 ... 0x205E).contains(currentChar)
                    || (0x2190 ... 0x23FF).contains(currentChar) || (0x2500 ... 0x2775).contains(currentChar)
                    || (0x2794 ... 0x2BFF).contains(currentChar) || (0x2E00 ... 0x2E7F).contains(currentChar)
                    || (0x3001 ... 0x3003).contains(currentChar) || (0x3008 ... 0x3020).contains(currentChar)
                    || currentChar == 0x3030
                {
                    return true
                } else if (0x0300 ... 0x036F).contains(currentChar)
                    || (0x1DC0 ... 0x1DFF).contains(currentChar) || (0x20D0 ... 0x20FF).contains(currentChar)
                    || (0xFE00 ... 0xFE0F).contains(currentChar) || (0xFE20 ... 0xFE2F).contains(currentChar)
                    || (0xE0100 ... 0xE01EF).contains(currentChar)
                {
                    return !isFirstChar
                }
                return false
        }
    }

    static func operatorAllowsLookahead(_ lookahead: UInt32, group: IllegalTerminatorGroup) -> Bool {
        // See "Operators": https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID418
        switch lookahead {
            case ascii("/"), ascii("="), ascii("-"), ascii("+"), ascii("!"), ascii("*"), ascii("%"),
                ascii("<"), ascii(">"), ascii("&"), ascii("|"), ascii("^"), ascii("?"), ascii("~"):
                if group == .operatorSymbols { return false }
                fallthrough
            case ascii("."):
                if group == .operatorOrDot { return false }
                fallthrough
            default:
                if isAlphanumeric(lookahead) && group == .alphanumeric { return false }
                if !isWhitespace(lookahead) && group == .nonWhitespace { return false }
                return true
        }
    }

    static func byte(_ value: [UInt8], at index: Int) -> UInt32 {
        index < value.count ? UInt32(value[index]) : 0
    }

    // Preserve the pinned scanner's operator loop and its match precedence.
    // swiftlint:disable:next cyclomatic_complexity
    static func eatOperators(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], markEnd: Bool,
        priorChar: UInt32, symbolResult: inout TokenType?
    ) -> Bool {
        var possibleOperators: UInt32 = 0
        for index in operators.indices
        where validSymbols[operatorSymbols[index].rawValue]
            && (priorChar == 0 || byte(operators[index], at: 0) == priorChar)
        {
            possibleOperators |= 1 << index
        }
        var possibleReservedOperators: UInt32 = 0
        for index in reservedOperators.indices
        where priorChar == 0 || byte(reservedOperators[index], at: 0) == priorChar {
            possibleReservedOperators |= 1 << index
        }
        var completeReservedOperators: UInt32 = 0

        var possibleCustomOperator = validSymbols[TokenType.customOperator.rawValue]
        let firstChar = priorChar == 0 ? lexer.lookahead : priorChar
        var lastExaminedChar = firstChar
        var stringIndex = priorChar == 0 ? 0 : 1
        var fullMatch = -1
        while true {
            for index in operators.indices where possibleOperators & (1 << index) != 0 {
                let expected = byte(operators[index], at: stringIndex)
                if expected == 0 {
                    // Make sure that the operator is allowed to have the next character as its lookahead.
                    if operatorAllowsLookahead(lexer.lookahead, group: operatorIllegalTerminators[index]) {
                        fullMatch = index
                        if markEnd { lexer.markEnd() }
                    }
                    possibleOperators &= ~(1 << index)
                    continue
                }
                if expected != lexer.lookahead { possibleOperators &= ~(1 << index) }
            }

            for index in reservedOperators.indices where possibleReservedOperators & (1 << index) != 0 {
                let expected = byte(reservedOperators[index], at: stringIndex)
                if expected == 0 || expected != lexer.lookahead {
                    possibleReservedOperators &= ~(1 << index)
                    completeReservedOperators &= ~(1 << index)
                    continue
                }
                if byte(reservedOperators[index], at: stringIndex + 1) == 0 {
                    completeReservedOperators |= 1 << index
                }
            }

            possibleCustomOperator =
                possibleCustomOperator
                && isLegalCustomOperator(stringIndex, firstChar: firstChar, currentChar: lexer.lookahead)
            let encounteredOperators = possibleOperators.nonzeroBitCount
            if encounteredOperators == 0 {
                if !possibleCustomOperator { break }
                if markEnd && fullMatch == -1 { lexer.markEnd() }
            }
            lastExaminedChar = lexer.lookahead
            lexer.advance(skip: false)
            stringIndex += 1
            if encounteredOperators == 0
                && !isLegalCustomOperator(stringIndex, firstChar: firstChar, currentChar: lexer.lookahead)
            {
                break
            }
        }

        if fullMatch != -1 {
            // We have a match -- first see if that match has a symbol that suppresses it. For example, in `try!`, we do
            // not want to emit the `!` as a symbol in our scanner, because we want the parser to have the chance to
            // parse it as an immediate token.
            if operatorSymbols[fullMatch] == .bang && validSymbols[TokenType.fakeTryBang.rawValue] { return false }
            symbolResult = operatorSymbols[fullMatch]
            return true
        }
        if possibleCustomOperator && completeReservedOperators == 0 {
            if (lastExaminedChar != ascii("<") || isWhitespace(lexer.lookahead)) && markEnd {
                lexer.markEnd()
            }
            symbolResult = .customOperator
            return true
        }
        return false
    }
}
