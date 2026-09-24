import AtelierParser

private func markdownIsAlpha(_ value: UInt32) -> Bool {
    Unicode.Scalar(value)?.properties.isAlphabetic == true
}

private func markdownIsAlnum(_ value: UInt32) -> Bool {
    guard let properties = Unicode.Scalar(value)?.properties else { return false }
    return properties.isAlphabetic || properties.numericType != nil
}

extension MarkdownExternalScanner {
    static let htmlTagNamesRule1 = ["pre", "script", "style"]
    static let htmlTagNamesRule7 = [
        "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center",
        "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head",
        "header", "hr", "html", "iframe", "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol", "optgroup", "option", "p", "param", "section", "source", "summary", "table",
        "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul"
    ]

    private static func htmlNameEquals(_ tag: String, name: InlineArray<10, UInt8>, length: Int) -> Bool {
        guard tag.utf8.count == length else { return false }
        for (index, byte) in tag.utf8.enumerated() where name[index] != byte { return false }
        return true
    }

    // The seven HTML block rules share lookahead in the source scanner.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    mutating func parseHTMLBlock(_ lexer: inout some ScannerLexer, validSymbols valid: [Bool]) -> Bool {
        guard (Token.htmlBlock1Start.rawValue ... Token.htmlBlock7Start.rawValue).contains(where: { valid[$0] }) else {
            return false
        }
        advance(&lexer)
        if lexer.lookahead == 63 && valid[Token.htmlBlock3Start.rawValue] {
            advance(&lexer)
            guard simulate || pushBlock(.anonymous) else { return false }
            lexer.resultSymbol = Token.htmlBlock3Start.rawValue
            return true
        }
        if lexer.lookahead == 33 {
            advance(&lexer)
            if lexer.lookahead == 45 {
                advance(&lexer)
                if lexer.lookahead == 45 && valid[Token.htmlBlock2Start.rawValue] {
                    advance(&lexer)
                    guard simulate || pushBlock(.anonymous) else { return false }
                    lexer.resultSymbol = Token.htmlBlock2Start.rawValue
                    return true
                }
            } else if (65 ... 90).contains(lexer.lookahead) && valid[Token.htmlBlock4Start.rawValue] {
                advance(&lexer)
                guard simulate || pushBlock(.anonymous) else { return false }
                lexer.resultSymbol = Token.htmlBlock4Start.rawValue
                return true
            } else if lexer.lookahead == 91 {
                advance(&lexer)
                var matchedCDATA = true
                for scalar: UInt32 in [67, 68, 65, 84, 65] {
                    if lexer.lookahead != scalar {
                        matchedCDATA = false
                        break
                    }
                    advance(&lexer)
                }
                if matchedCDATA && lexer.lookahead == 91 && valid[Token.htmlBlock5Start.rawValue] {
                    advance(&lexer)
                    guard simulate || pushBlock(.anonymous) else { return false }
                    lexer.resultSymbol = Token.htmlBlock5Start.rawValue
                    return true
                }
            }
        }
        let startingSlash = lexer.lookahead == 47
        if startingSlash { advance(&lexer) }
        var nameBytes = InlineArray<10, UInt8>(repeating: 0)
        var nameLength = 0
        while markdownIsAlpha(lexer.lookahead) {
            if nameLength < 10 {
                let scalar = lexer.lookahead
                nameBytes[nameLength] = UInt8(truncatingIfNeeded: (65 ... 90).contains(scalar) ? scalar + 32 : scalar)
                nameLength += 1
            } else {
                nameLength = 12
            }
            advance(&lexer)
        }
        guard nameLength > 0 else { return false }
        var tagClosed = false
        if nameLength < 11 {
            let nextSymbolValid =
                lexer.lookahead == 32 || lexer.lookahead == 9
                || Self.isNewline(lexer.lookahead) || lexer.lookahead == 62
            if nextSymbolValid
                && Self.htmlTagNamesRule1.contains(where: {
                    Self.htmlNameEquals($0, name: nameBytes, length: nameLength)
                })
            {
                if startingSlash {
                    if valid[Token.htmlBlock1End.rawValue] {
                        lexer.resultSymbol = Token.htmlBlock1End.rawValue
                        return true
                    }
                } else if valid[Token.htmlBlock1Start.rawValue] {
                    guard simulate || pushBlock(.anonymous) else { return false }
                    lexer.resultSymbol = Token.htmlBlock1Start.rawValue
                    return true
                }
            }
            if !nextSymbolValid && lexer.lookahead == 47 {
                advance(&lexer)
                if lexer.lookahead == 62 {
                    advance(&lexer)
                    tagClosed = true
                }
            }
            if (nextSymbolValid || tagClosed)
                && Self.htmlTagNamesRule7.contains(where: {
                    Self.htmlNameEquals($0, name: nameBytes, length: nameLength)
                })
                && valid[Token.htmlBlock6Start.rawValue]
            {
                guard simulate || pushBlock(.anonymous) else { return false }
                lexer.resultSymbol = Token.htmlBlock6Start.rawValue
                return true
            }
        }
        guard valid[Token.htmlBlock7Start.rawValue] else { return false }
        if !tagClosed {
            while markdownIsAlnum(lexer.lookahead) || lexer.lookahead == 45 { advance(&lexer) }
            if !startingSlash {
                var hadWhitespace = false
                while true {
                    while lexer.lookahead == 32 || lexer.lookahead == 9 {
                        hadWhitespace = true
                        advance(&lexer)
                    }
                    if lexer.lookahead == 47 {
                        advance(&lexer)
                        break
                    }
                    if lexer.lookahead == 62 { break }
                    guard
                        hadWhitespace
                            && (markdownIsAlpha(lexer.lookahead)
                                || lexer.lookahead == 95 || lexer.lookahead == 58)
                    else { return false }
                    hadWhitespace = false
                    advance(&lexer)
                    while markdownIsAlnum(lexer.lookahead) || lexer.lookahead == 95
                        || lexer.lookahead == 46 || lexer.lookahead == 58 || lexer.lookahead == 45
                    {
                        advance(&lexer)
                    }
                    while lexer.lookahead == 32 || lexer.lookahead == 9 {
                        hadWhitespace = true
                        advance(&lexer)
                    }
                    if lexer.lookahead == 61 {
                        advance(&lexer)
                        hadWhitespace = false
                        while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
                        if lexer.lookahead == 39 || lexer.lookahead == 34 {
                            let delimiter = lexer.lookahead
                            advance(&lexer)
                            while lexer.lookahead != delimiter && !Self.isNewline(lexer.lookahead)
                                && !lexer.isAtEnd
                            { advance(&lexer) }
                            guard lexer.lookahead == delimiter else { return false }
                            advance(&lexer)
                        } else {
                            var hadOne = false
                            while lexer.lookahead != 32 && lexer.lookahead != 9
                                && lexer.lookahead != 34 && lexer.lookahead != 39
                                && lexer.lookahead != 61 && lexer.lookahead != 60
                                && lexer.lookahead != 62 && lexer.lookahead != 96
                                && !Self.isNewline(lexer.lookahead) && !lexer.isAtEnd
                            {
                                advance(&lexer)
                                hadOne = true
                            }
                            if !hadOne { return false }
                        }
                    }
                }
            } else {
                while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
            }
            guard lexer.lookahead == 62 else { return false }
            advance(&lexer)
        }
        while lexer.lookahead == 32 || lexer.lookahead == 9 { advance(&lexer) }
        if Self.isNewline(lexer.lookahead) {
            guard simulate || pushBlock(.anonymous) else { return false }
            lexer.resultSymbol = Token.htmlBlock7Start.rawValue
            return true
        }
        return false
    }
}
