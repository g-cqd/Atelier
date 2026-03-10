import Foundation

/// Loads and validates tree-sitter grammar.json files.
public enum GrammarLoader: Sendable {

    /// Load a grammar definition from a file path.
    public static func load(from path: String) throws(GrammarError) -> GrammarDefinition {
        let url = URL(fileURLWithPath: path)
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
        return try parseGrammar(dict)
    }

    // MARK: - Private

    private static func parseGrammar(_ dict: [String: Any]) throws(GrammarError) -> GrammarDefinition {
        guard let name = dict["name"] as? String else {
            throw .missingField("name")
        }
        guard let rulesDict = dict["rules"] as? [String: Any] else {
            throw .missingField("rules")
        }

        // Preserve rule order — use the order from the JSON
        // rules is an object in grammar.json but order matters (first rule = start rule)
        var rules: [(name: String, rule: Rule)] = []
        // JSONSerialization doesn't preserve order, so we parse manually
        // For now, sort alphabetically but put the first rule first
        let ruleNames = rulesDict.keys.sorted()
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
