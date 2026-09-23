// Port of fwcd/tree-sitter-kotlin/src/scanner.c at f3a1ea74304adad67164a0a6ffe729428748a7a7.
// Copyright (c) 2019 fwcd. Licensed under the MIT License.

import AtelierParser

private func isKotlinSemicolonSpace(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isWhitespace == true
}

extension KotlinExternalScanner {
    func scanAutomaticSemicolon(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        lexer.resultSymbol = TokenType.automaticSemicolon.rawValue
        lexer.markEnd()

        var sameLine = true
        while true {
            if lexer.isAtEnd { return true }
            if lexer.lookahead == 59 {
                lexer.advance(skip: false)
                lexer.markEnd()
                return true
            }
            if !isKotlinSemicolonSpace(lexer.lookahead) { break }
            if lexer.lookahead == 10 {
                lexer.advance(skip: true)
                sameLine = false
                break
            }
            if lexer.lookahead == 13 {
                lexer.advance(skip: true)
                if lexer.lookahead == 10 { lexer.advance(skip: true) }
                sameLine = false
                break
            }
            lexer.advance(skip: true)
        }

        // Skip whitespace and comments (the C helper only skips whitespace).
        while isKotlinSemicolonSpace(lexer.lookahead) { lexer.advance(skip: true) }
        if sameLine {
            switch lexer.lookahead {
                // Insert an imaginary semicolon before an 'import', but not
                // other words or keywords starting with 'i'.
                case 105: return Self.scanForWord(&lexer, word: "mport")
                case 59:
                    lexer.advance(skip: false)
                    lexer.markEnd()
                    return true
                default: return false
            }
        }

        switch lexer.lookahead {
            case 44, 46, 58, 42, 37, 62, 60, 61, 123, 91, 40, 63, 124, 38:
                return false
            case 47:
                lexer.advance(skip: false)
                if lexer.lookahead == 47 { return scanLineCommentAfterNewline(&lexer) }
                if lexer.lookahead == 42 { return scanBlockCommentAfterNewline(&lexer) }
                // Bare '/' is division. No ASI.
                return false
            // In Kotlin, + and - after a newline are prefix operators.
            // A binary operation puts the operator at the end of the prior line.
            case 43, 45: return true
            // Don't insert before !=, but do before unary !.
            case 33:
                lexer.advance(skip: true)
                return lexer.lookahead != 61
            case 101: return !Self.scanForWord(&lexer, word: "lse")
            case 97: return !Self.scanForWord(&lexer, word: "s")
            case 119: return !Self.scanForWord(&lexer, word: "here")
            case 105, 112:
                // Don't insert before a visibility modifier followed by
                // 'constructor' in a class declaration context.
                if validSymbols[TokenType.primaryConstructorKeyword.rawValue]
                    && !validSymbols[TokenType.stringContent.rawValue]
                    && Self.checkModifierThenConstructor(&lexer)
                {
                    return false
                }
                return true
            case 99:
                // A primary constructor after a newline is emitted directly.
                // In error recovery all symbols are valid, so STRING_CONTENT
                // prevents this path and ASI wins.
                if validSymbols[TokenType.primaryConstructorKeyword.rawValue]
                    && !validSymbols[TokenType.stringContent.rawValue]
                {
                    if Self.scanConstructorKeyword(&lexer) { return true }
                    // After a partial keyword, catch cannot be checked reliably.
                    return true
                }
                return !Self.scanForWord(&lexer, word: "atch")
            case 102: return !Self.scanForWord(&lexer, word: "inally")
            case 59:
                lexer.advance(skip: false)
                lexer.markEnd()
                return true
            default: return true
        }
    }

    private func scanLineCommentAfterNewline(_ lexer: inout some ScannerLexer) -> Bool {
        // The line comment is an internal token. Skip it and check the next
        // real token, leaving the original ASI mark at the line break.
        lexer.advance(skip: true)
        skipLineCommentBody(&lexer)
        while isKotlinSemicolonSpace(lexer.lookahead) { lexer.advance(skip: true) }
        while lexer.lookahead == 47 {
            lexer.advance(skip: true)
            if lexer.lookahead == 47 {
                lexer.advance(skip: true)
                skipLineCommentBody(&lexer)
                while isKotlinSemicolonSpace(lexer.lookahead) { lexer.advance(skip: true) }
            } else if lexer.lookahead == 42 {
                lexer.advance(skip: true)
                var depth = 1
                var star = false
                while depth > 0 && !lexer.isAtEnd {
                    if lexer.lookahead == 42 {
                        lexer.advance(skip: true)
                        star = true
                    } else if lexer.lookahead == 47 {
                        lexer.advance(skip: true)
                        if star {
                            star = false
                            depth -= 1
                        } else {
                            if lexer.lookahead == 42 {
                                depth += 1
                                lexer.advance(skip: true)
                            }
                            star = false
                        }
                    } else {
                        star = false
                        lexer.advance(skip: true)
                    }
                }
                while isKotlinSemicolonSpace(lexer.lookahead) { lexer.advance(skip: true) }
            } else {
                // A lone '/' after a comment is division. Tree-sitter resets
                // to the original position before retrying internal lexing.
                return false
            }
        }
        switch lexer.lookahead {
            case 46, 44, 58, 42, 37, 62, 60, 61, 123, 91, 40, 63, 124, 38, 47:
                return false
            case 33:
                lexer.advance(skip: true)
                return lexer.lookahead != 61
            case 101: return !Self.scanForWord(&lexer, word: "lse")
            case 97: return !Self.scanForWord(&lexer, word: "s")
            case 119: return !Self.scanForWord(&lexer, word: "here")
            case 99: return !Self.scanForWord(&lexer, word: "atch")
            case 102: return !Self.scanForWord(&lexer, word: "inally")
            default: return true
        }
    }

    private func skipLineCommentBody(_ lexer: inout some ScannerLexer) {
        while lexer.lookahead != 10 && lexer.lookahead != 13 && lexer.lookahead != 0 && !lexer.isAtEnd {
            lexer.advance(skip: true)
        }
    }

    private func scanBlockCommentAfterNewline(_ lexer: inout some ScannerLexer) -> Bool {
        // Read through the comment with advance(), so the content is available
        // if the result becomes MULTILINE_COMMENT. Defer mark_end until the
        // following token decides between the comment and ASI.
        lexer.advance(skip: false)
        var depth = 1
        var afterStar = false
        while depth > 0 && !lexer.isAtEnd {
            switch lexer.lookahead {
                case 42:
                    lexer.advance(skip: false)
                    afterStar = true
                case 47:
                    lexer.advance(skip: false)
                    if afterStar {
                        afterStar = false
                        depth -= 1
                    } else {
                        if lexer.lookahead == 42 {
                            depth += 1
                            lexer.advance(skip: false)
                        }
                        afterStar = false
                    }
                default:
                    lexer.advance(skip: false)
                    afterStar = false
            }
        }
        if depth > 0 && lexer.isAtEnd {
            // Unterminated block comment at EOF.
            lexer.resultSymbol = TokenType.multilineComment.rawValue
            lexer.markEnd()
            return true
        }
        // Do not skip further comments: each must appear separately in the tree.
        while isKotlinSemicolonSpace(lexer.lookahead) { lexer.advance(skip: true) }
        switch lexer.lookahead {
            case 46, 44, 58, 37, 62, 60, 61, 123, 91, 40, 63, 124, 38, 47, 42:
                lexer.markEnd()
                lexer.resultSymbol = TokenType.multilineComment.rawValue
                return true
            case 33:
                // Mark before lookahead, so '!' is not swallowed.
                lexer.markEnd()
                lexer.advance(skip: true)
                if lexer.lookahead == 61 {
                    lexer.resultSymbol = TokenType.multilineComment.rawValue
                }
                return true
            case 101:
                lexer.markEnd()
                if Self.scanForWord(&lexer, word: "lse") {
                    lexer.resultSymbol = TokenType.multilineComment.rawValue
                }
                return true
            case 97:
                lexer.markEnd()
                if Self.scanForWord(&lexer, word: "s") {
                    lexer.resultSymbol = TokenType.multilineComment.rawValue
                }
                return true
            case 119:
                lexer.markEnd()
                if Self.scanForWord(&lexer, word: "here") {
                    lexer.resultSymbol = TokenType.multilineComment.rawValue
                }
                return true
            default:
                // ASI keeps the original zero-width mark; the block comment
                // is scanned as MULTILINE_COMMENT on the next parse step.
                return true
        }
    }
}
