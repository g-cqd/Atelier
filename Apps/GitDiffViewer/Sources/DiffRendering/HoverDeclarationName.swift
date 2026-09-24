import Foundation

/// The name Quick Help titles a symbol with, read from its Swift declaration: `Bool` for `@frozen struct Bool`,
/// `contains(_:)` for `func contains(_ element: Element) -> Bool`, `default` for ``class var `default` ``.
package enum HoverDeclarationName {
    /// Keywords that introduce a declaration; `class` and `static` also serve as modifiers, handled apart.
    private static let introducers: Set<String> = [
        "struct", "class", "enum", "protocol", "actor", "extension", "typealias", "associatedtype", "func", "init",
        "deinit", "subscript", "var", "let", "case", "macro", "precedencegroup", "operator"
    ]
    /// Declarations whose title carries their argument labels.
    private static let labelled: Set<String> = ["func", "init", "subscript", "macro", "case"]
    /// Words that may follow `class` when it is a modifier, as in `class var` or `class override func`.
    private static let modifiers: Set<String> = [
        "public", "private", "internal", "fileprivate", "open", "package", "final", "override", "static", "mutating",
        "nonmutating", "convenience", "required", "dynamic", "lazy", "weak", "unowned", "nonisolated", "indirect",
        "optional", "prefix", "postfix", "infix", "consuming", "borrowing", "distributed"
    ]

    /// The symbol's name, or nil when `declaration` introduces none this reader recognizes, as a tuple pattern.
    package static func name(fromDeclaration declaration: String) -> String? {
        let tokens = tokenize(declaration)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("@") {
                index = skipAttribute(tokens, from: index + 1)
                continue
            }
            let next = index + 1 < tokens.count ? tokens[index + 1] : ""
            if introducers.contains(token),
                !(token == "class" && (introducers.contains(next) || modifiers.contains(next)))
            {
                return name(introducedBy: token, tokens: tokens, after: index + 1)
            }
            index += 1
        }
        return nil
    }

    private static func name(introducedBy keyword: String, tokens: [String], after start: Int) -> String? {
        switch keyword {
            case "init", "deinit", "subscript":
                return keyword == "deinit"
                    ? "deinit" : withLabels(keyword, keyword: keyword, tokens: tokens, from: start)
            default:
                // A `func` may be named by an operator's spelling; a type's name may be qualified, as `Swift.Array`.
                var index = start
                guard index < tokens.count else { return nil }
                var base = unticked(tokens[index])
                guard base != "(" else { return nil }
                index += 1
                // An operator's spelling may span tokens, as `<=`, whose `<` the tokenizer splits off.
                if isOperatorSpelling(base) {
                    while index < tokens.count, tokens[index] != "(", isOperatorSpelling(tokens[index]) {
                        base += tokens[index]
                        index += 1
                    }
                }
                guard labelled.contains(keyword) else {
                    while index + 1 < tokens.count, tokens[index] == ".",
                        tokens[index + 1].first.map({ $0.isLetter || $0 == "_" || $0 == "`" }) == true
                    {
                        base += "." + unticked(tokens[index + 1])
                        index += 2
                    }
                    return base
                }
                return withLabels(base, keyword: keyword, tokens: tokens, from: index)
        }
    }

    /// `base` followed by its parameter list's argument labels, `base(a:_:)`, once any generic clause is skipped; `base`
    /// alone when no parameter list follows, as for an enum case without associated values.
    private static func withLabels(_ base: String, keyword: String, tokens: [String], from start: Int) -> String {
        var index = start
        while index < tokens.count, tokens[index] == "?" || tokens[index] == "!" { index += 1 }
        if index < tokens.count, tokens[index] == "<" {
            index = skipBalanced(tokens, from: index, open: "<", close: ">")
        }
        guard index < tokens.count, tokens[index] == "(" else { return base }
        let isOperator = isOperatorSpelling(base)
        let labels = parameterLabels(tokens, from: index + 1)
            .map { parameter -> String in
                let names = parameter.names
                if isOperator { return "_" }
                // An enum case's associated value is labelled only when a colon follows its name, as `case some(Wrapped)`.
                if keyword == "case" { return parameter.hasColon ? (names.first ?? "_") : "_" }
                // Two names are a label and a name; a subscript's lone name is no label, a function's is both.
                guard names.count >= 2 else { return keyword == "subscript" ? "_" : (names.first ?? "_") }
                return names[0]
            }
        return base + "(" + labels.map { $0 + ":" }.joined() + ")"
    }

    /// The names before each top-level parameter's colon, in the list starting after its opening parenthesis.
    private static func parameterLabels(
        _ tokens: [String], from start: Int
    ) -> [(names: [String], hasColon: Bool)] {
        var parameters: [(names: [String], hasColon: Bool)] = []
        var names: [String] = []
        var sawColon = false
        var depth = 0
        var index = start
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if ["(", "[", "<"].contains(token) {
                depth += 1
            } else if [")", "]", ">"].contains(token) {
                if depth == 0 {
                    if !names.isEmpty { parameters.append((names, sawColon)) }
                    return parameters
                }
                depth -= 1
            } else if depth == 0, token == "," {
                parameters.append((names.isEmpty ? ["_"] : names, sawColon))
                names = []
                sawColon = false
            } else if depth == 0, token == ":" {
                sawColon = true
            } else if depth == 0, !sawColon, token.first.map({ $0.isLetter || $0 == "_" || $0 == "`" }) == true {
                names.append(unticked(token))
            }
        }
        return parameters
    }

    /// The index after an attribute's name and its parenthesized arguments, if any.
    private static func skipAttribute(_ tokens: [String], from start: Int) -> Int {
        var index = start
        if index < tokens.count, tokens[index] == "(" {
            index = skipBalanced(tokens, from: index, open: "(", close: ")")
        }
        return index
    }

    /// The index after the bracket closing the one at `start`.
    private static func skipBalanced(_ tokens: [String], from start: Int, open: String, close: String) -> Int {
        var depth = 0
        var index = start
        while index < tokens.count {
            if tokens[index] == open { depth += 1 }
            if tokens[index] == close {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return index
    }

    /// Identifiers (backticked ones whole), attributes with their `@`, runs of operator characters, and each bracket
    /// or punctuation mark on its own.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character == "`" {
                var end = index + 1
                while end < characters.count, characters[end] != "`" { end += 1 }
                tokens.append(String(characters[index ... min(end, characters.count - 1)]))
                index = end + 1
            } else if character.isLetter || character.isNumber || character == "_" || character == "@"
                || character == "$" || character == "#"
            {
                var end = index + 1
                while end < characters.count,
                    characters[end].isLetter || characters[end].isNumber || characters[end] == "_"
                {
                    end += 1
                }
                tokens.append(String(characters[index ..< end]))
                index = end
            } else if character == "-", index + 1 < characters.count, characters[index + 1] == ">" {
                tokens.append("->")
                index += 2
            } else if "()<>[],:".contains(character) {
                tokens.append(String(character))
                index += 1
            } else if operatorCharacters.contains(character) {
                var end = index + 1
                while end < characters.count, operatorCharacters.contains(characters[end]),
                    !"<>".contains(characters[end])
                {
                    end += 1
                }
                tokens.append(String(characters[index ..< end]))
                index = end
            } else {
                tokens.append(String(character))
                index += 1
            }
        }
        return tokens
    }

    private static let operatorCharacters = Set("/=-+!*%<>&|^~?.")

    private static func isOperatorSpelling(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy(operatorCharacters.contains)
    }

    private static func unticked(_ token: String) -> String {
        guard token.count >= 2, token.hasPrefix("`"), token.hasSuffix("`") else { return token }
        return String(token.dropFirst().dropLast())
    }
}
