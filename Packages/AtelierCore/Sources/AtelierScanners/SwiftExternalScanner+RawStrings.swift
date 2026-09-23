import AtelierParser

extension SwiftExternalScanner {
    static let directives: [[UInt8]] = ["if", "elseif", "else", "endif"].map { Array($0.utf8) }
    static let directiveSymbols: [TokenType] = [.directiveIf, .directiveElseif, .directiveElse, .directiveEndif]

    static func findPossibleCompilerDirective(_ lexer: inout some ScannerLexer) -> TokenType {
        var possibleDirectives: UInt8 = 0b1111
        var stringIndex = 0
        var fullMatch = -1
        while true {
            for index in directives.indices where possibleDirectives & (1 << index) != 0 {
                let expected = byte(directives[index], at: stringIndex)
                if expected == 0 {
                    fullMatch = index
                    lexer.markEnd()
                    possibleDirectives &= ~(1 << index)
                    continue
                }
                if expected != lexer.lookahead { possibleDirectives &= ~(1 << index) }
            }
            if possibleDirectives == 0 { break }
            lexer.advance(skip: false)
            stringIndex += 1
        }
        if fullMatch == -1 {
            // No compiler directive found, so just match the starting symbol
            return .hashSymbol
        }
        return directiveSymbols[fullMatch]
    }

    mutating func eatRawStringPart(
        _ lexer: inout some ScannerLexer, validSymbols: [Bool], symbolResult: inout TokenType?
    ) -> Bool {
        var hashCount = ongoingRawStringHashCount
        if !validSymbols[TokenType.rawStrPart.rawValue] {
            return false
        } else if hashCount == 0 {
            // If this is a raw_str_part, it's the first one - look for hashes
            while lexer.lookahead == Self.ascii("#") {
                hashCount &+= 1
                lexer.advance(skip: false)
            }
            if hashCount == 0 { return false }
            if lexer.lookahead == Self.ascii("\"") {
                lexer.advance(skip: false)
            } else if hashCount == 1 {
                lexer.markEnd()
                symbolResult = Self.findPossibleCompilerDirective(&lexer)
                return true
            } else {
                return false
            }
        } else if validSymbols[TokenType.rawStrContinuingIndicator.rawValue] {
            // This is the end of an interpolation - now it's another raw_str_part. This is a synthetic
            // marker to tell us that the grammar just consumed a `(` symbol to close a raw
            // interpolation (since we don't want to fire on every `(` in existence). We don't have
            // anything to do except continue.
        } else {
            return false
        }

        // We're in a state where anything other than `hash_count` hash symbols in a row should be eaten
        // and is part of a string.
        // The last character _before_ the hashes will tell us what happens next.
        // Matters are also complicated by the fact that we don't want to consume every character we
        // visit; if we see a `\#(`, for instance, with the appropriate number of hash symbols, we want
        // to end our parsing _before_ that sequence. This allows highlighting tools to treat that as a
        // separate token.
        while lexer.lookahead != 0 {
            var lastChar: UInt8 = 0
            lexer.markEnd()  // We always want to parse thru the start of the string so far
            // Advance through anything that isn't a hash symbol, because we want to count those.
            while lexer.lookahead != Self.ascii("#") && lexer.lookahead != 0 {
                lastChar = UInt8(truncatingIfNeeded: lexer.lookahead)
                lexer.advance(skip: false)
                if lastChar != UInt8(ascii: "\\") || lexer.lookahead == Self.ascii("\\") {
                    // Mark a new end, but only if we didn't just advance past a `\` symbol, since we
                    // don't want to consume that. Exception: if this is a `\` that happens _right
                    // after_ another `\`, we for some reason _do_ want to consume that, because
                    // apparently that is parsed as a literal `\` followed by something escaped.
                    lexer.markEnd()
                }
            }

            // We hit at least one hash - count them and see if they match.
            var currentHashCount: UInt32 = 0
            while lexer.lookahead == Self.ascii("#") && currentHashCount < hashCount {
                currentHashCount += 1
                lexer.advance(skip: false)
            }

            // If we saw exactly the right number of hashes, one of three things is true:
            // 1. We're trying to interpolate into this string.
            // 2. The string just ended.
            // 3. This was just some hash characters doing nothing important.
            if currentHashCount == hashCount {
                if lastChar == UInt8(ascii: "\\") && lexer.lookahead == Self.ascii("(") {
                    // Interpolation case! Don't consume those chars; they get saved for grammar.js.
                    symbolResult = .rawStrPart
                    ongoingRawStringHashCount = hashCount
                    return true
                } else if lastChar == UInt8(ascii: "\"") {
                    // The string is finished! Mark the end here, on the very last hash symbol.
                    lexer.markEnd()
                    symbolResult = .rawStrEndPart
                    ongoingRawStringHashCount = 0
                    return true
                }
                // Nothing special happened - let the string continue.
            }
        }
        return false
    }
}
