// Port of fwcd/tree-sitter-kotlin/src/scanner.c at f3a1ea74304adad67164a0a6ffe729428748a7a7.
// Copyright (c) 2019 fwcd. Licensed under the MIT License.

import AtelierParser

private func isKotlinStringAlpha(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isAlphabetic == true
}

extension KotlinExternalScanner {
    // Pretty much all of this code is taken from the Julia tree-sitter parser.
    // Julia has similar problems with multiline comments that can be nested,
    // line comments, as well as line and multiline strings.
    // The most heavily edited section is scan_string_content, particularly
    // with respect to interpolation.

    // Block comments are easy to parse, but strings require extra-attention.
    // Triple quoted strings allow single quotes inside. e.g. """ "foo" """.
    // Non-standard string literals don't allow interpolations or escape
    // sequences, but you can always write \" and \`.
    // To efficiently store a delimiter, we use the fact that '"' is even,
    // storing a triple quoted delimiter as delimiter + 1.
    mutating func scanStringStart(_ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == 34, delimiters.count < maximumSerializedScannerStateSize else { return false }
        lexer.advance(skip: false)
        lexer.markEnd()
        for _ in 1 ..< 3 {
            if lexer.lookahead != 34 {
                // It's not a triple quoted delimiter.
                delimiters.append(34)
                return true
            }
            lexer.advance(skip: false)
        }
        lexer.markEnd()
        delimiters.append(35)
        return true
    }

    mutating func scanStringContent(_ lexer: inout some ScannerLexer) -> Bool {
        guard let delimiter = delimiters.last else { return false }  // Stack is empty. We're not in a string.
        let isTriple = delimiter & 1 != 0
        let endChar: UInt32 = UInt32(isTriple ? delimiter - 1 : delimiter)
        var hasContent = false
        while lexer.lookahead != 0 {
            if lexer.lookahead == 36 {
                // If we did not just start reading stuff, stop here so the grammar
                // has the opportunity to lex an interpolated identifier.
                if hasContent {
                    lexer.resultSymbol = TokenType.stringContent.rawValue
                    return true
                }
                // Otherwise determine whether it starts an interpolation.
                lexer.advance(skip: false)
                if isKotlinStringAlpha(lexer.lookahead) || lexer.lookahead == 123 { return false }
                lexer.resultSymbol = TokenType.stringContent.rawValue
                lexer.markEnd()
                return true
            }
            if lexer.lookahead == 92 {
                // An escaped dollar sign is content, not an interpolation.
                lexer.advance(skip: false)
                if lexer.lookahead == 36 {
                    lexer.advance(skip: false)
                    // An escaped dollar sign at the end of a string needs to
                    // terminate the string properly.
                    if lexer.lookahead == endChar {
                        delimiters.removeLast()
                        lexer.advance(skip: false)
                        lexer.markEnd()
                        lexer.resultSymbol = TokenType.stringEnd.rawValue
                        return true
                    }
                }
            } else if lexer.lookahead == endChar {
                if isTriple {
                    lexer.markEnd()
                    for _ in 1 ..< 3 {
                        lexer.advance(skip: false)
                        if lexer.lookahead != endChar {
                            lexer.markEnd()
                            lexer.resultSymbol = TokenType.stringContent.rawValue
                            return true
                        }
                    }
                    // For """foo""", at 'f', quit after 'foo' and ascribe it
                    // to STRING_CONTENT rather than absorbing it into STRING_END.
                    if hasContent && lexer.lookahead == endChar {
                        lexer.resultSymbol = TokenType.stringContent.rawValue
                        return true
                    }
                    // The internals are hidden in the tree, so a run of quotes
                    // belongs to STRING_END rather than separate tokens.
                    lexer.resultSymbol = TokenType.stringEnd.rawValue
                    lexer.markEnd()
                    while lexer.lookahead == endChar {
                        lexer.advance(skip: false)
                        lexer.markEnd()
                    }
                    delimiters.removeLast()
                    return true
                }
                if hasContent {
                    lexer.markEnd()
                    lexer.resultSymbol = TokenType.stringContent.rawValue
                    return true
                }
                delimiters.removeLast()
                lexer.advance(skip: false)
                lexer.markEnd()
                lexer.resultSymbol = TokenType.stringEnd.rawValue
                return true
            }
            lexer.advance(skip: false)
            hasContent = true
        }
        return false
    }

    mutating func scanMultilineComment(_ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == 47 else { return false }
        lexer.advance(skip: false)
        guard lexer.lookahead == 42 else { return false }
        lexer.advance(skip: false)

        var afterStar = false
        var nestingDepth = 1
        while true {
            switch lexer.lookahead {
                case 42:
                    lexer.advance(skip: false)
                    afterStar = true
                case 47:
                    lexer.advance(skip: false)
                    if afterStar {
                        afterStar = false
                        nestingDepth -= 1
                        if nestingDepth == 0 {
                            lexer.resultSymbol = TokenType.multilineComment.rawValue
                            lexer.markEnd()
                            return true
                        }
                    } else {
                        afterStar = false
                        if lexer.lookahead == 42 {
                            nestingDepth += 1
                            lexer.advance(skip: false)
                        }
                    }
                case 0:
                    // Accept unterminated block comments at EOF rather than
                    // rejecting them, as JetBrains PSI recognizes unclosed /*.
                    if lexer.isAtEnd {
                        lexer.resultSymbol = TokenType.multilineComment.rawValue
                        lexer.markEnd()
                        return true
                    }
                    return false
                default:
                    lexer.advance(skip: false)
                    afterStar = false
            }
        }
    }
}
