import AemiJSONCore
public import Foundation

/// Loads and validates tree-sitter grammar.json files.
public enum GrammarLoader: Sendable {
    private static let maxGrammarFileSize = 10_000_000  // 10MB

    /// The deepest container nesting a grammar may have. It bounds the recursive rule walk: the deepest bundled
    /// grammar nests 26 levels, and 64 stays far below what a 512 KiB cooperative-pool stack survives.
    static let maxNestingDepth = 64

    private static let parseOptions = JSONParseOptions(maxDepth: maxNestingDepth)

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
    ///
    /// The data is UTF-8 JSON; a leading byte-order mark is skipped. Rules keep their document order, and a key
    /// repeated in one object keeps its first value.
    /// - Throws: `GrammarError.invalidJSON` when the data is not JSON, nests deeper than 64 levels, has no object at
    ///   its root, or has a `rules` member that is not an object; `.missingField` or `.invalidRuleType` when a member
    ///   a grammar needs is absent or has the wrong shape.
    /// - Complexity: O(n) in the size of the data.
    public static func parse(_ data: Data) throws(GrammarError) -> GrammarDefinition {
        let document: JSONDocument
        do {
            document = try AemiJSON.parse(bytesSkippingByteOrderMark(data), options: parseOptions)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        guard document.root.isObject else {
            throw .invalidJSON("Root must be an object")
        }
        return try parseGrammar(GrammarMembers(document.root))
    }

    // MARK: - Private

    private static func bytesSkippingByteOrderMark(_ data: Data) -> [UInt8] {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        return data.starts(with: byteOrderMark) ? Array(data.dropFirst(byteOrderMark.count)) : Array(data)
    }

    private static func parseGrammar(_ grammar: GrammarMembers) throws(GrammarError) -> GrammarDefinition {
        if let rules = grammar.rules, !rules.isObject {
            throw .invalidJSON("Expected object for 'rules'")
        }
        guard let name = grammar.name?.string else {
            throw .missingField("name")
        }
        guard let rules = grammar.rules else {
            throw .missingField("rules")
        }

        let parsedRules = try parseNamedRules(rules)
        let extras = try parseRuleList(grammar.extras)
        let conflicts = grammar.conflicts.flatMap(stringLists) ?? []
        let externals = try parseRuleList(grammar.externals)
        let inline = grammar.inline.flatMap(strings) ?? []
        let word = grammar.word?.string
        let supertypes = grammar.supertypes.flatMap(strings) ?? []
        let precedences = try parsePrecedences(grammar.precedences)

        return GrammarDefinition(
            name: name,
            rules: parsedRules,
            extras: extras,
            conflicts: conflicts,
            externals: externals,
            inline: inline,
            word: word,
            supertypes: supertypes,
            precedences: precedences
        )
    }

    /// The rules of the `rules` object in document order; a repeated rule name keeps its first definition.
    private static func parseNamedRules(_ object: JSON) throws(GrammarError) -> [(name: String, rule: Rule)] {
        var definitions: [(name: String, node: JSON)] = []
        definitions.reserveCapacity(object.count)
        var seen = Set<String>()
        object.forEachMember { name, node in
            if seen.insert(name).inserted { definitions.append((name, node)) }
        }
        var rules: [(name: String, rule: Rule)] = []
        rules.reserveCapacity(definitions.count)
        for definition in definitions {
            rules.append((name: definition.name, rule: try parseRule(definition.node)))
        }
        return rules
    }

    /// The rules of an array member; an absent member, or one that is not an array, holds none.
    private static func parseRuleList(_ node: JSON?) throws(GrammarError) -> [Rule] {
        guard let elements = node?.array else { return [] }
        return try parseRules(elements)
    }

    private static func parseRules(_ elements: [JSON]) throws(GrammarError) -> [Rule] {
        var rules: [Rule] = []
        rules.reserveCapacity(elements.count)
        for element in elements { rules.append(try parseRule(element)) }
        return rules
    }

    /// Recurses once per nested rule, so the parse's depth limit bounds the stack it uses.
    private static func parseRule(_ node: JSON) throws(GrammarError) -> Rule {
        guard node.isObject else {
            throw .invalidRuleType("Expected object, got \(kindName(of: node))")
        }
        let rule = RuleMembers(node)
        guard let type = rule.type?.string else {
            throw .missingField("type in rule")
        }

        switch type {
            case "SYMBOL":
                return .symbol(try requiredString(rule.name, "name"))
            case "STRING":
                return .string(try requiredString(rule.value, "value"))
            case "PATTERN":
                return .pattern(try requiredString(rule.value, "value"))
            case "SEQ":
                return .seq(try parseRules(requiredArray(rule.members, "members")))
            case "CHOICE":
                return .choice(try parseRules(requiredArray(rule.members, "members")))
            case "REPEAT":
                return .repeat(try parseRule(requiredContent(rule)))
            case "REPEAT1":
                return .repeat1(try parseRule(requiredContent(rule)))
            case "OPTIONAL":  // tree-sitter uses CHOICE with BLANK for optional
                return .optional(try parseRule(requiredContent(rule)))
            case "PREC":
                return .prec(try requiredInteger(rule.value), try parseRule(requiredContent(rule)))
            case "PREC_LEFT":
                return .precLeft(try requiredInteger(rule.value), try parseRule(requiredContent(rule)))
            case "PREC_RIGHT":
                return .precRight(try requiredInteger(rule.value), try parseRule(requiredContent(rule)))
            case "PREC_DYNAMIC":
                return .precDynamic(try requiredInteger(rule.value), try parseRule(requiredContent(rule)))
            case "TOKEN":
                return .token(try parseRule(requiredContent(rule)))
            case "IMMEDIATE_TOKEN":
                return .immediateToken(try parseRule(requiredContent(rule)))
            case "FIELD":
                return .field(try requiredString(rule.name, "name"), try parseRule(requiredContent(rule)))
            case "ALIAS":
                let content = try requiredContent(rule)
                let value = try requiredString(rule.value, "value")
                return .alias(try parseRule(content), value, rule.named.flatMap(flag) ?? false)
            case "BLANK":
                return .blank
            default:
                throw .invalidRuleType(type)
        }
    }

    private static func parsePrecedences(_ node: JSON?) throws(GrammarError) -> [[PrecedenceEntry]] {
        guard let groups = node?.array, groups.allSatisfy(\.isArray) else { return [] }
        var result: [[PrecedenceEntry]] = []
        result.reserveCapacity(groups.count)
        for group in groups {
            var entries: [PrecedenceEntry] = []
            for entry in group.arrayValue { entries.append(try precedenceEntry(entry)) }
            result.append(entries)
        }
        return result
    }

    /// A precedence entry: a symbol name, or a `STRING` or `SYMBOL` rule object.
    private static func precedenceEntry(_ node: JSON) throws(GrammarError) -> PrecedenceEntry {
        if let symbol = node.string { return .symbol(symbol) }
        let entry = RuleMembers(node)
        switch entry.type?.string {
            case "STRING":
                if let value = entry.value?.string { return .literal(value) }
            case "SYMBOL":
                if let name = entry.name?.string { return .symbol(name) }
            default:
                break
        }
        throw .invalidRuleType("Invalid precedence entry")
    }

    // MARK: - Member values

    private static func requiredString(_ node: JSON?, _ field: String) throws(GrammarError) -> String {
        guard let string = node?.string else { throw .missingField(field) }
        return string
    }

    private static func requiredArray(_ node: JSON?, _ field: String) throws(GrammarError) -> [JSON] {
        guard let elements = node?.array else { throw .missingField(field) }
        return elements
    }

    /// A rule's `content`, which may hold any JSON value; `parseRule` rejects one that is not a rule.
    private static func requiredContent(_ rule: RuleMembers) throws(GrammarError) -> JSON {
        guard let content = rule.content else { throw .missingField("content") }
        return content
    }

    private static func requiredInteger(_ node: JSON?) throws(GrammarError) -> Int {
        guard let value = node.flatMap(integer) else { throw .missingField("value") }
        return value
    }

    /// `node` as an integer: a number with an exact integer value, or a boolean as 1 or 0.
    private static func integer(_ node: JSON) -> Int? {
        if let bool = node.bool { return bool ? 1 : 0 }
        return node.int ?? node.double.flatMap { Int(exactly: $0) }
    }

    /// `node` as a flag: a boolean, or the number 1 or 0.
    private static func flag(_ node: JSON) -> Bool? {
        if let bool = node.bool { return bool }
        guard let number = node.double, number == 1 || number == 0 else { return nil }
        return number == 1
    }

    /// The elements of an array of strings; nil when `node` is not an array or holds anything but strings.
    private static func strings(_ node: JSON) -> [String]? {
        guard let elements = node.array else { return nil }
        let strings = elements.compactMap(\.string)
        return strings.count == elements.count ? strings : nil
    }

    /// The elements of an array of string arrays; nil when any element is not one.
    private static func stringLists(_ node: JSON) -> [[String]]? {
        guard let elements = node.array else { return nil }
        let lists = elements.compactMap(strings)
        return lists.count == elements.count ? lists : nil
    }

    /// The kind of a node that is not an object, for error messages.
    private static func kindName(of node: JSON) -> String {
        if node.isArray { return "array" }
        if node.isNull { return "null" }
        if node.bool != nil { return "boolean" }
        if node.double != nil { return "number" }
        return "string"
    }
}

/// The top-level members a grammar reads, each the first of its key.
private struct GrammarMembers {
    var name: JSON?
    var rules: JSON?
    var extras: JSON?
    var conflicts: JSON?
    var externals: JSON?
    var inline: JSON?
    var word: JSON?
    var supertypes: JSON?
    var precedences: JSON?

    /// Visits `object`'s members once. A node that is not an object leaves every member nil.
    init(_ object: JSON) {
        object.forEachMember { key, value in
            switch key {
                case "name": name = name ?? value
                case "rules": rules = rules ?? value
                case "extras": extras = extras ?? value
                case "conflicts": conflicts = conflicts ?? value
                case "externals": externals = externals ?? value
                case "inline": inline = inline ?? value
                case "word": word = word ?? value
                case "supertypes": supertypes = supertypes ?? value
                case "precedences": precedences = precedences ?? value
                default: break
            }
        }
    }
}

/// The members a rule object, or a precedence entry, reads, each the first of its key.
private struct RuleMembers {
    var type: JSON?
    var name: JSON?
    var value: JSON?
    var content: JSON?
    var members: JSON?
    var named: JSON?

    /// Visits `object`'s members once. A node that is not an object leaves every member nil.
    init(_ object: JSON) {
        object.forEachMember { key, member in
            switch key {
                case "type": type = type ?? member
                case "name": name = name ?? member
                case "value": value = value ?? member
                case "content": content = content ?? member
                case "members": members = members ?? member
                case "named": named = named ?? member
                default: break
            }
        }
    }
}
