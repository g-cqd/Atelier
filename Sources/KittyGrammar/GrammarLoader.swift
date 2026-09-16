public import Foundation

/// Loads and validates tree-sitter grammar.json files.
public enum GrammarLoader: Sendable {

    private static let maxGrammarFileSize = 10_000_000  // 10MB

    /// Load a grammar definition from a file path.
    public static func load(from path: String) throws(GrammarError) -> GrammarDefinition {
        let url = URL(fileURLWithPath: path)
        // Check file size before loading
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let fileSize = attrs[.size] as? Int,
            fileSize > maxGrammarFileSize
        {
            throw .invalidJSON(
                "Grammar file too large (\(fileSize) bytes, limit \(maxGrammarFileSize))")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .fileNotFound(path)
        }
        return try parse(data)
    }

    /// Load a grammar definition from raw JSON data.
    public static func parse(_ data: Data) throws(GrammarError) -> GrammarDefinition {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        guard let dict = json as? [String: Any] else {
            throw .invalidJSON("Root must be an object")
        }
        let ruleOrder = try extractRuleOrder(from: data)
        return try parseGrammar(dict, ruleOrder: ruleOrder)
    }

    // MARK: - Private

    private static func parseGrammar(_ dict: [String: Any], ruleOrder: [String])
        throws(GrammarError) -> GrammarDefinition
    {
        guard let name = dict["name"] as? String else {
            throw .missingField("name")
        }
        guard let rulesDict = dict["rules"] as? [String: Any] else {
            throw .missingField("rules")
        }

        var rules: [(name: String, rule: Rule)] = []
        let ruleNames = orderedRuleNames(in: rulesDict, using: ruleOrder)
        for ruleName in ruleNames {
            guard let ruleJSON = rulesDict[ruleName] else { continue }
            let rule = try parseRule(ruleJSON)
            rules.append((name: ruleName, rule: rule))
        }

        var extras: [Rule] = []
        if let extrasArray = dict["extras"] as? [Any] {
            for item in extrasArray { extras.append(try parseRule(item)) }
        }
        let conflicts = (dict["conflicts"] as? [[String]]) ?? []
        var externals: [Rule] = []
        if let externalsArray = dict["externals"] as? [Any] {
            for item in externalsArray { externals.append(try parseRule(item)) }
        }
        let inline = (dict["inline"] as? [String]) ?? []
        let word = dict["word"] as? String
        let supertypes = (dict["supertypes"] as? [String]) ?? []
        let precedences = try parsePrecedences(dict["precedences"])

        return GrammarDefinition(
            name: name,
            rules: rules,
            extras: extras,
            conflicts: conflicts,
            externals: externals,
            inline: inline,
            word: word,
            supertypes: supertypes,
            precedences: precedences
        )
    }

    private static func parseRule(_ json: Any) throws(GrammarError) -> Rule {
        guard let dict = json as? [String: Any] else {
            throw .invalidRuleType("Expected object, got \(type(of: json))")
        }
        guard let type = dict["type"] as? String else {
            throw .missingField("type in rule")
        }

        switch type {
        case "SYMBOL":
            guard let name = dict["name"] as? String else { throw .missingField("name") }
            return .symbol(name)

        case "STRING":
            guard let value = dict["value"] as? String else { throw .missingField("value") }
            return .string(value)

        case "PATTERN":
            guard let value = dict["value"] as? String else { throw .missingField("value") }
            return .pattern(value)

        case "SEQ":
            guard let members = dict["members"] as? [Any] else { throw .missingField("members") }
            var seqRules: [Rule] = []
            for m in members { seqRules.append(try parseRule(m)) }
            return .seq(seqRules)

        case "CHOICE":
            guard let members = dict["members"] as? [Any] else { throw .missingField("members") }
            var choiceRules: [Rule] = []
            for m in members { choiceRules.append(try parseRule(m)) }
            return .choice(choiceRules)

        case "REPEAT":
            guard let content = dict["content"] else { throw .missingField("content") }
            return .repeat(try parseRule(content))

        case "REPEAT1":
            guard let content = dict["content"] else { throw .missingField("content") }
            return .repeat1(try parseRule(content))

        case "OPTIONAL":  // tree-sitter uses CHOICE with BLANK for optional
            guard let content = dict["content"] else { throw .missingField("content") }
            return .optional(try parseRule(content))

        case "PREC":
            guard let value = dict["value"] as? Int else { throw .missingField("value") }
            guard let content = dict["content"] else { throw .missingField("content") }
            return .prec(value, try parseRule(content))

        case "PREC_LEFT":
            guard let value = dict["value"] as? Int else { throw .missingField("value") }
            guard let content = dict["content"] else { throw .missingField("content") }
            return .precLeft(value, try parseRule(content))

        case "PREC_RIGHT":
            guard let value = dict["value"] as? Int else { throw .missingField("value") }
            guard let content = dict["content"] else { throw .missingField("content") }
            return .precRight(value, try parseRule(content))

        case "PREC_DYNAMIC":
            guard let value = dict["value"] as? Int else { throw .missingField("value") }
            guard let content = dict["content"] else { throw .missingField("content") }
            return .precDynamic(value, try parseRule(content))

        case "TOKEN":
            guard let content = dict["content"] else { throw .missingField("content") }
            return .token(try parseRule(content))

        case "IMMEDIATE_TOKEN":
            guard let content = dict["content"] else { throw .missingField("content") }
            return .immediateToken(try parseRule(content))

        case "FIELD":
            guard let name = dict["name"] as? String else { throw .missingField("name") }
            guard let content = dict["content"] else { throw .missingField("content") }
            return .field(name, try parseRule(content))

        case "ALIAS":
            guard let content = dict["content"] else { throw .missingField("content") }
            guard let value = dict["value"] as? String else { throw .missingField("value") }
            let named = dict["named"] as? Bool ?? false
            return .alias(try parseRule(content), value, named)

        case "BLANK":
            return .blank

        default:
            throw .invalidRuleType(type)
        }
    }

    private static func extractRuleOrder(from data: Data) throws(GrammarError) -> [String] {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw .invalidJSON("Grammar JSON must be UTF-8 encoded")
        }
        var scanner = JSONOrderScanner(source: jsonString)
        return try scanner.extractKeyOrder(for: "rules") ?? []
    }

    private static func orderedRuleNames(
        in rulesDict: [String: Any],
        using ruleOrder: [String]
    ) -> [String] {
        var orderedNames: [String] = []
        var seen = Set<String>()
        for ruleName in ruleOrder where rulesDict[ruleName] != nil {
            if seen.insert(ruleName).inserted {
                orderedNames.append(ruleName)
            }
        }
        let remainingNames = rulesDict.keys.filter { !seen.contains($0) }.sorted()
        return orderedNames + remainingNames
    }

    private static func parsePrecedences(_ json: Any?) throws(GrammarError) -> [[PrecedenceEntry]] {
        guard let array = json as? [[Any]] else { return [] }
        var result: [[PrecedenceEntry]] = []
        for group in array {
            var entries: [PrecedenceEntry] = []
            for entry in group {
                if let str = entry as? String {
                    entries.append(.symbol(str))
                } else if let dict = entry as? [String: Any], let type = dict["type"] as? String {
                    if type == "STRING", let value = dict["value"] as? String {
                        entries.append(.literal(value))
                    } else if type == "SYMBOL", let name = dict["name"] as? String {
                        entries.append(.symbol(name))
                    } else {
                        throw .invalidRuleType("Invalid precedence entry")
                    }
                } else {
                    throw .invalidRuleType("Invalid precedence entry")
                }
            }
            result.append(entries)
        }
        return result
    }
}

private struct JSONOrderScanner: Sendable {
    private let source: String
    private var index: String.Index

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    mutating func extractKeyOrder(for targetKey: String) throws(GrammarError) -> [String]? {
        skipWhitespace()
        guard consume("{") else {
            throw .invalidJSON("Root must be an object")
        }

        skipWhitespace()
        if consume("}") {
            return nil
        }

        while true {
            let key = try parseString()
            skipWhitespace()
            try consumeRequired(":", message: "Expected ':' after object key")
            skipWhitespace()

            if key == targetKey {
                return try parseObjectKeyOrder()
            }

            try skipValue()
            skipWhitespace()

            if consume("}") {
                return nil
            }

            try consumeRequired(",", message: "Expected ',' between object members")
            skipWhitespace()
        }
    }

    private mutating func parseObjectKeyOrder() throws(GrammarError) -> [String] {
        try consumeRequired("{", message: "Expected object for 'rules'")

        skipWhitespace()
        if consume("}") {
            return []
        }

        var keys: [String] = []

        while true {
            keys.append(try parseString())
            skipWhitespace()
            try consumeRequired(":", message: "Expected ':' after rule key")
            skipWhitespace()
            try skipValue()
            skipWhitespace()

            if consume("}") {
                return keys
            }

            try consumeRequired(",", message: "Expected ',' between rule definitions")
            skipWhitespace()
        }
    }

    private mutating func skipValue() throws(GrammarError) {
        skipWhitespace()

        guard let character = currentCharacter else {
            throw .invalidJSON("Unexpected end of JSON")
        }

        switch character {
        case "\"":
            _ = try parseString()
        case "{":
            try skipObject()
        case "[":
            try skipArray()
        default:
            skipScalarValue()
        }
    }

    private mutating func skipObject() throws(GrammarError) {
        try consumeRequired("{", message: "Expected object")
        skipWhitespace()

        if consume("}") {
            return
        }

        while true {
            _ = try parseString()
            skipWhitespace()
            try consumeRequired(":", message: "Expected ':' after object key")
            skipWhitespace()
            try skipValue()
            skipWhitespace()

            if consume("}") {
                return
            }

            try consumeRequired(",", message: "Expected ',' between object members")
            skipWhitespace()
        }
    }

    private mutating func skipArray() throws(GrammarError) {
        try consumeRequired("[", message: "Expected array")
        skipWhitespace()

        if consume("]") {
            return
        }

        while true {
            try skipValue()
            skipWhitespace()

            if consume("]") {
                return
            }

            try consumeRequired(",", message: "Expected ',' between array elements")
            skipWhitespace()
        }
    }

    private mutating func skipScalarValue() {
        while let character = currentCharacter, !character.isWhitespace,
            !isValueTerminator(character)
        {
            advance()
        }
    }

    private mutating func parseString() throws(GrammarError) -> String {
        try consumeRequired("\"", message: "Expected string")

        var result = String()

        while let character = currentCharacter {
            advance()

            if character == "\"" {
                return result
            }

            if character == "\\" {
                guard let escapedCharacter = currentCharacter else {
                    throw .invalidJSON("Unterminated escape sequence")
                }
                advance()
                try appendEscapedCharacter(escapedCharacter, to: &result)
                continue
            }

            result.append(character)
        }

        throw .invalidJSON("Unterminated string")
    }

    private mutating func appendEscapedCharacter(
        _ escapedCharacter: Character,
        to result: inout String
    ) throws(GrammarError) {
        switch escapedCharacter {
        case "\"":
            result.append("\"")
        case "\\":
            result.append("\\")
        case "/":
            result.append("/")
        case "b":
            result.append("\u{08}")
        case "f":
            result.append("\u{0C}")
        case "n":
            result.append("\n")
        case "r":
            result.append("\r")
        case "t":
            result.append("\t")
        case "u":
            try appendUnicodeEscape(to: &result)
        default:
            throw .invalidJSON("Unsupported escape sequence \\(escapedCharacter)")
        }
    }

    private mutating func appendUnicodeEscape(to result: inout String) throws(GrammarError) {
        let firstCodeUnit = try parseUnicodeEscapeCodeUnit()

        if Self.isHighSurrogate(firstCodeUnit) {
            try consumeRequired("\\", message: "Expected low surrogate following high surrogate")
            try consumeRequired("u", message: "Expected unicode escape following high surrogate")

            let secondCodeUnit = try parseUnicodeEscapeCodeUnit()
            guard Self.isLowSurrogate(secondCodeUnit) else {
                throw .invalidJSON("Invalid unicode escape surrogate pair")
            }

            let scalarValue = Self.supplementaryScalarValue(
                highSurrogate: firstCodeUnit,
                lowSurrogate: secondCodeUnit
            )
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw .invalidJSON("Invalid unicode escape surrogate pair")
            }

            result.unicodeScalars.append(scalar)
            return
        }

        guard !Self.isLowSurrogate(firstCodeUnit), let scalar = UnicodeScalar(firstCodeUnit) else {
            throw .invalidJSON("Invalid unicode escape surrogate pair")
        }

        result.unicodeScalars.append(scalar)
    }

    private mutating func parseUnicodeEscapeCodeUnit() throws(GrammarError) -> UInt32 {
        let start = index
        let end = source.index(start, offsetBy: 4, limitedBy: source.endIndex)
        guard let end else {
            throw .invalidJSON("Incomplete unicode escape")
        }

        let hex = String(source[start..<end])
        guard hex.count == 4, let codeUnit = UInt32(hex, radix: 16) else {
            throw .invalidJSON("Invalid unicode escape \\u\(hex)")
        }

        index = end
        return codeUnit
    }

    private mutating func consumeRequired(
        _ expected: Character,
        message: String
    ) throws(GrammarError) {
        guard consume(expected) else {
            throw .invalidJSON(message)
        }
    }

    private mutating func consume(_ expected: Character) -> Bool {
        guard currentCharacter == expected else {
            return false
        }

        advance()
        return true
    }

    private mutating func skipWhitespace() {
        while let character = currentCharacter, character.isWhitespace {
            advance()
        }
    }

    private var currentCharacter: Character? {
        guard index < source.endIndex else {
            return nil
        }
        return source[index]
    }

    private mutating func advance() {
        index = source.index(after: index)
    }

    private func isValueTerminator(_ character: Character) -> Bool {
        character == "," || character == "]" || character == "}"
    }

    private static func isHighSurrogate(_ value: UInt32) -> Bool {
        value >= 0xD800 && value <= 0xDBFF
    }

    private static func isLowSurrogate(_ value: UInt32) -> Bool {
        value >= 0xDC00 && value <= 0xDFFF
    }

    private static func supplementaryScalarValue(highSurrogate: UInt32, lowSurrogate: UInt32)
        -> UInt32
    {
        let highOffset = highSurrogate - 0xD800
        let lowOffset = lowSurrogate - 0xDC00
        return 0x10000 + (highOffset << 10) + lowOffset
    }
}
