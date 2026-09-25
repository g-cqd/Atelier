/// Parses tree-sitter `.scm` query files into Query objects.
///
/// Supported syntax:
/// ```scm
/// (function_declaration name: (identifier) @function.name)
/// "if" @keyword
/// (_) @named
/// _ @any
/// (identifier) @var (#eq? @var "self")
/// ```
public enum QueryParser: Sendable {
    private static let maxRecursionDepth = 128

    public static func parse(_ source: String) throws(QueryError) -> Query {
        var scanner = QueryScanner(source: source)
        var patterns: [QueryPattern] = []

        while scanner.skipWhitespaceAndComments() {
            if scanner.peek() == nil { break }
            let pattern = try parsePattern(&scanner)
            patterns.append(pattern)
        }

        return Query(patterns: patterns)
    }

    // MARK: - Private

    private static func parsePattern(_ scanner: inout QueryScanner) throws(QueryError) -> QueryPattern {
        scanner.depth += 1
        defer { scanner.depth -= 1 }
        guard scanner.depth <= maxRecursionDepth else {
            throw scanner.syntaxError("Query exceeds maximum nesting depth (\(maxRecursionDepth))")
        }

        scanner.skipWhitespaceAndComments()

        guard let ch = scanner.peek() else {
            throw scanner.syntaxError("Unexpected end of input")
        }

        var pattern: QueryPattern
        switch ch {
            case "(":
                pattern = try parseNodePattern(&scanner)
            case "\"":
                pattern = try parseLiteralPattern(&scanner)
            case "_":
                pattern = try parseWildcard(&scanner)
            case ".":
                pattern = parseAnchor(&scanner)
            case "[":
                pattern = try parseAlternation(&scanner)
            case "#":
                pattern = try parsePredicatePattern(&scanner)
            default:
                throw scanner.syntaxError("Unexpected character: \(ch)")
        }

        // Suffixes in any order and number, as tree-sitter reads them (ts_query__parse_pattern in lib/src/query.c):
        // captures, `(identifier) @var @name`, and quantifiers, which join, `(use_site_target)? @attribute`.
        var allCaptures: [QueryPattern.Capture] = []
        var quantifier: Quantifier?
        while true {
            scanner.skipWhitespaceAndComments()
            if scanner.peek() == "@" {
                if let capture = try parseCapture(&scanner) {
                    allCaptures.append(capture)
                }
            } else if let next = readQuantifier(&scanner) {
                quantifier = quantifier.map { $0.joined(with: next) } ?? next
            } else {
                break
            }
        }
        if let first = allCaptures.first {
            pattern = attachCapture(first, to: pattern)
            // Additional captures: wrap in a sequence with extra copies
            if allCaptures.count > 1 {
                var parts = [pattern]
                for extra in allCaptures.dropFirst() {
                    parts.append(attachCapture(extra, to: stripCapture(from: pattern)))
                }
                pattern = .sequence(parts)
            }
        }

        let predicates = try parsePredicates(&scanner)
        pattern = wrap(pattern, with: predicates)
        if let next = readQuantifier(&scanner) {
            quantifier = quantifier.map { $0.joined(with: next) } ?? next
        }
        if let quantifier {
            pattern = .quantified(pattern: pattern, quantifier: quantifier)
        }

        return pattern
    }

    private static func attachCapture(_ capture: QueryPattern.Capture?, to pattern: QueryPattern) -> QueryPattern {
        guard let capture else { return pattern }
        switch pattern {
            case .nodeMatch(let type, let children, let existing):
                return .nodeMatch(type: type, children: children, capture: existing ?? capture)
            case .literal(let value, let existing):
                return .literal(value, capture: existing ?? capture)
            case .wildcard(let existing):
                return .wildcard(capture: existing ?? capture)
            case .alternation(let patterns):
                return .alternation(patterns.map { attachCapture(capture, to: $0) })
            case .sequence(let patterns):
                guard !patterns.isEmpty else { return pattern }
                var updatedPatterns = patterns
                updatedPatterns[0] = attachCapture(capture, to: updatedPatterns[0])
                return .sequence(updatedPatterns)
            default:
                return pattern
        }
    }

    private static func parseNodePattern(_ scanner: inout QueryScanner) throws(QueryError)
        -> QueryPattern
    {
        scanner.advance()  // consume (
        scanner.skipWhitespaceAndComments()

        if scanner.peek() == "#" {
            let predicate = try parsePredicatePattern(&scanner)
            scanner.skipWhitespaceAndComments()
            guard scanner.peek() == ")" else {
                throw scanner.syntaxError("Expected )")
            }
            scanner.advance()
            return predicate
        }

        if scanner.isGroupStart() {
            var patterns: [QueryPattern] = []
            while let ch = scanner.peek(), ch != ")" {
                patterns.append(try parsePattern(&scanner))
                scanner.skipWhitespaceAndComments()
            }
            guard scanner.peek() == ")" else {
                throw scanner.syntaxError("Expected )")
            }
            scanner.advance()
            return patterns.count == 1 ? patterns[0] : .sequence(patterns)
        }

        // A wildcard node, `(_)`, or one with children, `(_ key: (flow_node))`, which matches a named node of any
        // type as tree-sitter's WILDCARD_SYMBOL step does: parenthesized, the step is named (`step->is_named` in
        // ts_query__parse_pattern, lib/src/query.c; docs "The Wildcard Node"). A bare `_` matches any node.
        if scanner.peek() == "_" {
            scanner.advance()
            scanner.skipWhitespaceAndComments()
            if let next = scanner.peek(), next != ")" && next != "@" && next != "#" {
                let children = try parseChildren(&scanner)
                return .nodeMatch(type: QueryPattern.namedWildcardType, children: children, capture: nil)
            }
            let capture = try parseCapture(&scanner)
            let predicates = try parsePredicates(&scanner)
            guard scanner.peek() == ")" else {
                throw scanner.syntaxError("Expected )")
            }
            scanner.advance()
            let node = QueryPattern.nodeMatch(type: QueryPattern.namedWildcardType, children: [], capture: capture)
            return wrap(node, with: predicates)
        }

        // Node type
        let type = scanner.readIdentifier()
        guard !type.isEmpty else {
            throw scanner.syntaxError("Expected node type")
        }

        scanner.skipWhitespaceAndComments()
        let children = try parseChildren(&scanner)

        // Capture will be attached by the caller (parsePattern)
        return .nodeMatch(type: type, children: children, capture: nil)
    }

    /// A node pattern's children, fields and predicates, through its closing parenthesis.
    private static func parseChildren(_ scanner: inout QueryScanner) throws(QueryError) -> [QueryPattern] {
        var children: [QueryPattern] = []
        while let ch = scanner.peek(), ch != ")" && ch != "@" && ch != "#" {
            if ch == "!" {
                // Negated field
                let fieldStart = scanner.position
                scanner.advance()
                let fieldName = scanner.readIdentifier()
                guard !fieldName.isEmpty else { throw fieldStart.syntaxError("Expected a field name after !") }
                children.append(.negatedField(fieldName))
            } else if scanner.isFieldPrefix() {
                let fieldStart = scanner.position
                let fieldName = scanner.readIdentifier()
                guard !fieldName.isEmpty else { throw fieldStart.syntaxError("Expected a field name before :") }
                guard scanner.peek() == ":" else {
                    throw scanner.syntaxError("Expected : after field name")
                }
                scanner.advance()
                scanner.skipWhitespaceAndComments()
                let child = try parsePattern(&scanner)
                children.append(.fieldMatch(name: fieldName, pattern: child))
            } else {
                let child = try parsePattern(&scanner)
                children.append(child)
            }
            scanner.skipWhitespaceAndComments()
        }

        // Predicates inside parens
        children.append(contentsOf: try parsePredicates(&scanner))

        guard scanner.peek() == ")" else {
            throw scanner.syntaxError("Expected )")
        }
        scanner.advance()
        return children
    }

    private static func parseLiteralPattern(_ scanner: inout QueryScanner) throws(QueryError)
        -> QueryPattern
    {
        let value = try scanner.readString()
        scanner.skipWhitespaceAndComments()
        let capture = try parseCapture(&scanner)
        return .literal(value, capture: capture)
    }

    private static func parseWildcard(_ scanner: inout QueryScanner) throws(QueryError) -> QueryPattern {
        scanner.advance()  // consume _
        scanner.skipWhitespaceAndComments()
        let capture = try parseCapture(&scanner)
        return .wildcard(capture: capture)
    }

    private static func parseAlternation(_ scanner: inout QueryScanner) throws(QueryError)
        -> QueryPattern
    {
        scanner.advance()  // consume [
        scanner.skipWhitespaceAndComments()
        var alternatives: [QueryPattern] = []
        while let ch = scanner.peek(), ch != "]" {
            alternatives.append(try parsePattern(&scanner))
            scanner.skipWhitespaceAndComments()
        }
        guard scanner.peek() == "]" else {
            throw scanner.syntaxError("Expected ]")
        }
        scanner.advance()
        return .alternation(alternatives)
    }

    private static func parseAnchor(_ scanner: inout QueryScanner) -> QueryPattern {
        scanner.advance()
        return .anchor
    }

    private static func parsePredicates(_ scanner: inout QueryScanner) throws(QueryError)
        -> [QueryPattern]
    {
        var predicates: [QueryPattern] = []

        while true {
            scanner.skipWhitespaceAndComments()

            if scanner.peek() == "#" {
                predicates.append(try parsePredicatePattern(&scanner))
                continue
            }

            if scanner.isParenthesizedPredicateStart() {
                predicates.append(try parseNodePattern(&scanner))
                continue
            }

            return predicates
        }
    }

    /// The capture at the scanner, unnumbered: ``Query`` numbers the captures of the patterns it holds.
    private static func parseCapture(_ scanner: inout QueryScanner) throws(QueryError) -> QueryPattern.Capture? {
        guard scanner.peek() == "@" else { return nil }
        let captureStart = scanner.position
        scanner.advance()
        let name = scanner.readCaptureName()
        guard !name.isEmpty else {
            throw captureStart.invalidCapture("Empty capture name")
        }
        scanner.definedCaptures.insert(name)
        return QueryPattern.Capture(name)
    }

    private static func wrap(_ pattern: QueryPattern, with predicates: [QueryPattern])
        -> QueryPattern
    {
        guard !predicates.isEmpty else { return pattern }
        return .sequence([pattern] + predicates)
    }

    private static func stripCapture(from pattern: QueryPattern) -> QueryPattern {
        switch pattern {
            case .nodeMatch(let type, let children, _):
                return .nodeMatch(type: type, children: children, capture: nil)
            case .literal(let value, _):
                return .literal(value, capture: nil)
            case .wildcard:
                return .wildcard(capture: nil)
            default:
                return pattern
        }
    }
}

// MARK: - Quantifiers

extension QueryParser {
    /// The quantifier at the scanner, consumed, or nil when there is none.
    private static func readQuantifier(_ scanner: inout QueryScanner) -> Quantifier? {
        let quantifier: Quantifier
        switch scanner.peek() {
            case "+": quantifier = .oneOrMore
            case "*": quantifier = .zeroOrMore
            case "?": quantifier = .optional
            default: return nil
        }
        scanner.advance()
        return quantifier
    }
}

extension Quantifier {
    /// Two quantifiers on one pattern, as tree-sitter's `quantifier_join` (lib/src/query.c) combines them: the same one
    /// twice is itself, and any other pair allows zero or more.
    fileprivate func joined(with other: Quantifier) -> Quantifier {
        self == other ? self : .zeroOrMore
    }
}

// MARK: - Predicates

extension QueryParser {
    private static func parsePredicatePattern(_ scanner: inout QueryScanner) throws(QueryError)
        -> QueryPattern
    {
        guard scanner.peek() == "#" else {
            throw scanner.syntaxError("Expected #")
        }

        // `#`, an identifier and `?` or `!`, as tree-sitter reads a predicate's name (ts_query__parse_predicate in
        // lib/src/query.c).
        let nameStart = scanner.position
        scanner.advance()
        let identifier = scanner.readIdentifier()
        guard !identifier.isEmpty, let suffix = scanner.peek(), suffix == "?" || suffix == "!" else {
            throw nameStart.syntaxError("Expected a predicate name ending in ? or ! after #")
        }
        scanner.advance()
        let predName = "#" + identifier + String(suffix)
        scanner.skipWhitespaceAndComments()

        // Arguments: captures, strings and bare symbols. Each one read advances the scanner, and anything else is an
        // error, so the loop ends.
        var args: [PredicateArgument] = []
        while let ch = scanner.peek(), ch != ")" && ch != "#" {
            if ch == "@" {
                let captureStart = scanner.position
                scanner.advance()
                let name = scanner.readCaptureName()
                guard !name.isEmpty else { throw captureStart.syntaxError("Expected a capture name after @") }
                // A capture the text has not defined yet is an error, as in ts_query__parse_predicate
                // (TSQueryErrorCapture, lib/src/query.c): it may come from an earlier pattern, never a later place.
                guard scanner.definedCaptures.contains(name) else {
                    throw captureStart.invalidCapture("Unknown capture @\(name)")
                }
                args.append(.capture(name))
            } else if ch == "\"" {
                args.append(.string(try scanner.readString()))
            } else {
                let symbolStart = scanner.position
                let symbol = scanner.readIdentifier()
                guard !symbol.isEmpty else {
                    throw symbolStart.syntaxError("Unexpected character \(ch.debugDescription) in a predicate")
                }
                args.append(.string(symbol))
            }
            scanner.skipWhitespaceAndComments()
        }

        let predicate = try buildPredicate(name: predName, args: args, at: nameStart)
        return .predicate(predicate)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func buildPredicate(name: String, args: [PredicateArgument], at position: QueryPosition)
        throws(QueryError) -> Predicate
    {
        switch name {
            case "#eq?":
                guard args.count >= 2 else { throw position.syntaxError("eq? requires 2 arguments") }
                let capture = try captureArgument(of: "eq?", args, at: position)
                if case .capture = args[1] { return .eqCapture(capture: capture, other: args[1].text) }
                return .eq(capture: capture, value: args[1].text)
            case "#not-eq?":
                guard args.count >= 2 else { throw position.syntaxError("not-eq? requires 2 arguments") }
                let capture = try captureArgument(of: "not-eq?", args, at: position)
                if case .capture = args[1] { return .notEqCapture(capture: capture, other: args[1].text) }
                return .notEq(capture: capture, value: args[1].text)
            case "#match?":
                guard args.count >= 2 else { throw position.syntaxError("match? requires 2 arguments") }
                return .match(capture: try captureArgument(of: "match?", args, at: position), pattern: args[1].text)
            case "#not-match?":
                guard args.count >= 2 else { throw position.syntaxError("not-match? requires 2 arguments") }
                let capture = try captureArgument(of: "not-match?", args, at: position)
                return .notMatch(capture: capture, pattern: args[1].text)
            case "#any-of?":
                guard args.count >= 2 else {
                    throw position.syntaxError("any-of? requires at least 2 arguments")
                }
                let capture = try captureArgument(of: "any-of?", args, at: position)
                return .anyOf(capture: capture, values: args.dropFirst().map(\.text))
            case "#contains?":
                guard args.count >= 2 else { throw position.syntaxError("contains? requires 2 arguments") }
                return .contains(capture: try captureArgument(of: "contains?", args, at: position), value: args[1].text)
            case "#is?":
                let property = try parseProperty(name: "is?", args: args, at: position)
                return .is(capture: property.capture, property: property.key, value: property.value)
            case "#is-not?":
                let property = try parseProperty(name: "is-not?", args: args, at: position)
                return .isNot(capture: property.capture, property: property.key, value: property.value)
            default:
                return .directive(name: name, arguments: args.map(\.text))
        }
    }

    /// The capture a text predicate tests, its first argument, which must be a capture as tree-sitter's Rust binding
    /// requires ("First argument to #eq? predicate must be a capture name", lib/binding_rust/lib.rs): a quoted "@name"
    /// is a string, not a capture.
    private static func captureArgument(of name: String, _ args: [PredicateArgument], at position: QueryPosition)
        throws(QueryError) -> String
    {
        guard case .capture = args[0] else {
            throw position.syntaxError("\(name) takes a capture first, got the string \(args[0].text.debugDescription)")
        }
        return args[0].text
    }

    /// The arguments of a property predicate, read as tree-sitter reads them (`parse_property` in its Rust binding):
    /// one to three, of which at most one is a capture, in any position; the first string is the key and the second,
    /// if any, its value. `(#is-not? local)` names no capture, `(#is? @node named)` one, and in `(#is? "@node" named)`
    /// the quoted "@node" is the key.
    private static func parseProperty(name: String, args: [PredicateArgument], at position: QueryPosition)
        throws(QueryError) -> (capture: String?, key: String, value: String?)
    {
        guard (1 ... 3).contains(args.count) else {
            throw position.syntaxError("\(name) takes 1 to 3 arguments, got \(args.count)")
        }
        var capture: String?
        var strings: [String] = []
        for argument in args {
            switch argument {
                case .capture:
                    guard capture == nil else { throw position.syntaxError("\(name) takes at most one capture") }
                    capture = argument.text
                case .string(let string):
                    strings.append(string)
            }
        }
        guard let key = strings.first else { throw position.syntaxError("\(name) requires a property name") }
        guard strings.count <= 2 else {
            throw position.syntaxError("\(name) takes one property name and one value")
        }
        return (capture, key, strings.dropFirst().first)
    }
}

/// A predicate's argument as the query writes it. Tree-sitter keeps captures and strings apart
/// (TSQueryPredicateStepTypeCapture and TSQueryPredicateStepTypeString in lib/src/query.c), so a quoted "@name" is a
/// string like any other, never a capture.
private enum PredicateArgument {
    /// `@name`, held without its `@`.
    case capture(String)
    /// A quoted string or a bare symbol.
    case string(String)

    /// The argument as ``Predicate`` holds it: a capture with its `@`, a string as it is.
    var text: String {
        switch self {
            case .capture(let name): "@" + name
            case .string(let string): string
        }
    }
}
