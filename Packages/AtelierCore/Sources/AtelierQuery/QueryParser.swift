/// Parses tree-sitter `.scm` query files into Query objects.
///
/// Supported syntax:
/// ```scm
/// (function_declaration name: (identifier) @function.name)
/// "if" @keyword
/// (_) @any
/// (identifier) @var (#eq? @var "self")
/// ```
public enum QueryParser: Sendable {
    private static let maxRecursionDepth = 128

    public static func parse(_ source: String) throws(QueryError) -> Query {
        var scanner = Scanner(source: source)
        var patterns: [QueryPattern] = []

        while scanner.skipWhitespaceAndComments() {
            if scanner.peek() == nil { break }
            let pattern = try parsePattern(&scanner)
            patterns.append(pattern)
        }

        return Query(patterns: patterns)
    }

    // MARK: - Private

    private static func parsePattern(_ scanner: inout Scanner) throws(QueryError) -> QueryPattern {
        scanner.depth += 1
        defer { scanner.depth -= 1 }
        guard scanner.depth <= maxRecursionDepth else {
            throw .syntaxError("Query exceeds maximum nesting depth (\(maxRecursionDepth))")
        }

        scanner.skipWhitespaceAndComments()

        guard let ch = scanner.peek() else {
            throw .syntaxError("Unexpected end of input")
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
                throw .syntaxError("Unexpected character: \(ch)")
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

    private static func parseNodePattern(_ scanner: inout Scanner) throws(QueryError)
        -> QueryPattern
    {
        scanner.advance()  // consume (
        scanner.skipWhitespaceAndComments()

        if scanner.peek() == "#" {
            let predicate = try parsePredicatePattern(&scanner)
            scanner.skipWhitespaceAndComments()
            guard scanner.peek() == ")" else {
                throw .syntaxError("Expected )")
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
                throw .syntaxError("Expected )")
            }
            scanner.advance()
            return patterns.count == 1 ? patterns[0] : .sequence(patterns)
        }

        // A wildcard node, `(_)`, or one with children, `(_ key: (flow_node))`, which matches a named node of any
        // type as tree-sitter's WILDCARD_SYMBOL step does (lib/src/query.c).
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
                throw .syntaxError("Expected )")
            }
            scanner.advance()
            return wrap(.wildcard(capture: capture), with: predicates)
        }

        // Node type
        let type = scanner.readIdentifier()
        guard !type.isEmpty else {
            throw .syntaxError("Expected node type")
        }

        scanner.skipWhitespaceAndComments()
        let children = try parseChildren(&scanner)

        // Capture will be attached by the caller (parsePattern)
        return .nodeMatch(type: type, children: children, capture: nil)
    }

    /// A node pattern's children, fields and predicates, through its closing parenthesis.
    private static func parseChildren(_ scanner: inout Scanner) throws(QueryError) -> [QueryPattern] {
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
                    throw .syntaxError("Expected : after field name")
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
            throw .syntaxError("Expected )")
        }
        scanner.advance()
        return children
    }

    private static func parseLiteralPattern(_ scanner: inout Scanner) throws(QueryError)
        -> QueryPattern
    {
        let value = try scanner.readString()
        scanner.skipWhitespaceAndComments()
        let capture = try parseCapture(&scanner)
        return .literal(value, capture: capture)
    }

    private static func parseWildcard(_ scanner: inout Scanner) throws(QueryError) -> QueryPattern {
        scanner.advance()  // consume _
        scanner.skipWhitespaceAndComments()
        let capture = try parseCapture(&scanner)
        return .wildcard(capture: capture)
    }

    private static func parseAlternation(_ scanner: inout Scanner) throws(QueryError)
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
            throw .syntaxError("Expected ]")
        }
        scanner.advance()
        return .alternation(alternatives)
    }

    private static func parseAnchor(_ scanner: inout Scanner) -> QueryPattern {
        scanner.advance()
        return .anchor
    }

    private static func parsePredicates(_ scanner: inout Scanner) throws(QueryError)
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
    private static func parseCapture(_ scanner: inout Scanner) throws(QueryError) -> QueryPattern.Capture? {
        guard scanner.peek() == "@" else { return nil }
        scanner.advance()
        let name = scanner.readCaptureName()
        guard !name.isEmpty else {
            throw .invalidCapture("Empty capture name")
        }
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
    private static func readQuantifier(_ scanner: inout Scanner) -> Quantifier? {
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
    private static func parsePredicatePattern(_ scanner: inout Scanner) throws(QueryError)
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
        var args: [String] = []
        while let ch = scanner.peek(), ch != ")" && ch != "#" {
            if ch == "@" {
                let captureStart = scanner.position
                scanner.advance()
                let name = scanner.readCaptureName()
                guard !name.isEmpty else { throw captureStart.syntaxError("Expected a capture name after @") }
                args.append("@" + name)
            } else if ch == "\"" {
                let str = try scanner.readString()
                args.append(str)
            } else {
                let symbolStart = scanner.position
                let symbol = scanner.readIdentifier()
                guard !symbol.isEmpty else {
                    throw symbolStart.syntaxError("Unexpected character \(ch.debugDescription) in a predicate")
                }
                args.append(symbol)
            }
            scanner.skipWhitespaceAndComments()
        }

        let predicate = try buildPredicate(name: predName, args: args)
        return .predicate(predicate)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func buildPredicate(name: String, args: [String]) throws(QueryError) -> Predicate {
        switch name {
            case "#eq?":
                guard args.count >= 2 else { throw .syntaxError("eq? requires 2 arguments") }
                return .eq(capture: args[0], value: args[1])
            case "#not-eq?":
                guard args.count >= 2 else { throw .syntaxError("not-eq? requires 2 arguments") }
                return .notEq(capture: args[0], value: args[1])
            case "#match?":
                guard args.count >= 2 else { throw .syntaxError("match? requires 2 arguments") }
                return .match(capture: args[0], pattern: args[1])
            case "#not-match?":
                guard args.count >= 2 else { throw .syntaxError("not-match? requires 2 arguments") }
                return .notMatch(capture: args[0], pattern: args[1])
            case "#any-of?":
                guard args.count >= 2 else {
                    throw .syntaxError("any-of? requires at least 2 arguments")
                }
                return .anyOf(capture: args[0], values: Array(args.dropFirst()))
            case "#contains?":
                guard args.count >= 2 else { throw .syntaxError("contains? requires 2 arguments") }
                return .contains(capture: args[0], value: args[1])
            case "#is?":
                let property = try parseProperty(name: "is?", args: args)
                return .is(capture: property.capture, property: property.key, value: property.value)
            case "#is-not?":
                let property = try parseProperty(name: "is-not?", args: args)
                return .isNot(capture: property.capture, property: property.key, value: property.value)
            default:
                return .directive(name: name, arguments: args)
        }
    }

    /// The arguments of a property predicate, read as tree-sitter reads them (`parse_property` in its Rust binding):
    /// one to three, of which at most one is a capture, in any position; the first string is the key and the second,
    /// if any, its value. `(#is-not? local)` names no capture, `(#is? @node named)` one.
    private static func parseProperty(name: String, args: [String]) throws(QueryError)
        -> (capture: String?, key: String, value: String?)
    {
        guard (1 ... 3).contains(args.count) else {
            throw .syntaxError("\(name) takes 1 to 3 arguments, got \(args.count)")
        }
        var capture: String?
        var strings: [String] = []
        for argument in args {
            if argument.hasPrefix("@") {
                guard capture == nil else { throw .syntaxError("\(name) takes at most one capture") }
                capture = argument
            } else {
                strings.append(argument)
            }
        }
        guard let key = strings.first else { throw .syntaxError("\(name) requires a property name") }
        guard strings.count <= 2 else { throw .syntaxError("\(name) takes one property name and one value") }
        return (capture, key, strings.dropFirst().first)
    }
}

// MARK: - Scanner

private struct Scanner: Sendable {
    var source: String
    var index: String.Index
    var depth: Int = 0

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    var isAtEnd: Bool { index >= source.endIndex }

    /// Where the scanner stands, to name in an error.
    var position: Position { Position(source: source, index: index) }

    /// A syntax error at the scanner's position.
    func syntaxError(_ message: String) -> QueryError {
        position.syntaxError(message)
    }

    func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return source[index]
    }

    mutating func advance() {
        guard !isAtEnd else { return }
        index = source.index(after: index)
    }

    @discardableResult
    mutating func skipWhitespaceAndComments() -> Bool {
        while let ch = peek() {
            if ch.isWhitespace {
                advance()
            } else if ch == ";" {
                // Line comment
                while let c = peek(), c != "\n" { advance() }
            } else {
                break
            }
        }
        return !isAtEnd
    }

    mutating func readIdentifier() -> String {
        var result = ""
        while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-" {
            result.append(ch)
            advance()
        }
        return result
    }

    mutating func readCaptureName() -> String {
        var result = ""
        while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-" {
            result.append(ch)
            advance()
        }
        return result
    }

    mutating func readString() throws(QueryError) -> String {
        guard peek() == "\"" else { throw syntaxError("Expected a string") }
        let start = position
        advance()
        var result = ""
        while let ch = peek(), ch != "\"" {
            if ch == "\\" {
                advance()
                if let escaped = peek() {
                    result.append(escaped)
                    advance()
                }
            } else {
                result.append(ch)
                advance()
            }
        }
        guard peek() == "\"" else { throw start.syntaxError("Unterminated string") }
        advance()
        return result
    }

    func isFieldPrefix() -> Bool {
        // Look ahead for pattern: identifier followed by ':'
        var tempIdx = index
        while tempIdx < source.endIndex {
            let ch = source[tempIdx]
            if ch.isLetter || ch.isNumber || ch == "_" {
                tempIdx = source.index(after: tempIdx)
            } else if ch == ":" {
                return true
            } else {
                return false
            }
        }
        return false
    }

    func isParenthesizedPredicateStart() -> Bool {
        guard peek() == "(" else { return false }

        var tempIdx = source.index(after: index)
        while tempIdx < source.endIndex {
            let ch = source[tempIdx]

            if ch.isWhitespace {
                tempIdx = source.index(after: tempIdx)
                continue
            }

            if ch == ";" {
                while tempIdx < source.endIndex, source[tempIdx] != "\n" {
                    tempIdx = source.index(after: tempIdx)
                }
                continue
            }

            return ch == "#"
        }

        return false
    }

    func isGroupStart() -> Bool {
        guard let next = peek() else { return false }
        return next == "(" || next == "[" || next == "\"" || next == "."
    }
}

/// A place in a query's text, which an error names by line and column; both count from 1, the column in characters.
private struct Position: Sendable {
    var source: String
    var index: String.Index

    /// A syntax error at this position.
    func syntaxError(_ message: String) -> QueryError {
        var line = 1
        var column = 1
        for character in source[..<index] {
            if character == "\n" || character == "\r\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return .syntaxError("\(message) at line \(line), column \(column)")
    }
}
