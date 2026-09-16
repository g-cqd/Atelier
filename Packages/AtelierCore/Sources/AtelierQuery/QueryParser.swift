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

        // Check for trailing captures after pattern (e.g., (identifier) @var @name)
        scanner.skipWhitespaceAndComments()
        var allCaptures: [String] = []
        while scanner.peek() == "@" {
            if let capture = try parseCapture(&scanner) {
                allCaptures.append(capture)
            }
            scanner.skipWhitespaceAndComments()
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
        pattern = applyQuantifier(pattern, scanner: &scanner)

        return pattern
    }

    private static func attachCapture(_ capture: String?, to pattern: QueryPattern) -> QueryPattern {
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

        // Check for wildcard (_)
        if scanner.peek() == "_" {
            scanner.advance()
            scanner.skipWhitespaceAndComments()
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

        // Children and fields
        var children: [QueryPattern] = []
        while let ch = scanner.peek(), ch != ")" && ch != "@" && ch != "#" {
            if ch == "!" {
                // Negated field
                scanner.advance()
                let fieldName = scanner.readIdentifier()
                children.append(.negatedField(fieldName))
            } else if scanner.isFieldPrefix() {
                let fieldName = scanner.readIdentifier()
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

        // Capture will be attached by the caller (parsePattern)
        return .nodeMatch(type: type, children: children, capture: nil)
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

    private static func parsePredicatePattern(_ scanner: inout Scanner) throws(QueryError)
        -> QueryPattern
    {
        guard scanner.peek() == "#" else {
            throw .syntaxError("Expected #")
        }

        let predName = scanner.readUntil { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == ")" }
        scanner.skipWhitespaceAndComments()

        // Parse arguments
        var args: [String] = []
        while let ch = scanner.peek(), ch != ")" && ch != "#" && ch != "\n" {
            if ch == "@" {
                scanner.advance()
                args.append("@" + scanner.readIdentifier())
            } else if ch == "\"" {
                let str = try scanner.readString()
                args.append(str)
            } else {
                args.append(scanner.readIdentifier())
            }
            scanner.skipWhitespaceAndComments()
        }

        let predicate = try buildPredicate(name: predName, args: args)
        return .predicate(predicate)
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

    private static func parseCapture(_ scanner: inout Scanner) throws(QueryError) -> String? {
        guard scanner.peek() == "@" else { return nil }
        scanner.advance()
        let name = scanner.readCaptureName()
        guard !name.isEmpty else {
            throw .invalidCapture("Empty capture name")
        }
        return name
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
                guard args.count >= 2 else { throw .syntaxError("is? requires 2 arguments") }
                return .is(capture: args[0], property: args[1])
            case "#is-not?":
                guard args.count >= 2 else { throw .syntaxError("is-not? requires 2 arguments") }
                return .isNot(capture: args[0], property: args[1])
            default:
                return .directive(name: name, arguments: args)
        }
    }

    private static func wrap(_ pattern: QueryPattern, with predicates: [QueryPattern])
        -> QueryPattern
    {
        guard !predicates.isEmpty else { return pattern }
        return .sequence([pattern] + predicates)
    }

    private static func applyQuantifier(_ pattern: QueryPattern, scanner: inout Scanner)
        -> QueryPattern
    {
        guard let next = scanner.peek(), next == "+" || next == "*" || next == "?" else {
            return pattern
        }
        scanner.advance()
        let quantifier: Quantifier
        switch next {
            case "+": quantifier = .oneOrMore
            case "*": quantifier = .zeroOrMore
            default: quantifier = .optional
        }
        return .quantified(pattern: pattern, quantifier: quantifier)
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
        guard peek() == "\"" else { throw .syntaxError("Expected string") }
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
        guard peek() == "\"" else { throw .syntaxError("Unterminated string") }
        advance()
        return result
    }

    mutating func readUntil(_ stop: (Character) -> Bool) -> String {
        var result = ""
        while let ch = peek(), !stop(ch) {
            result.append(ch)
            advance()
        }
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
        return next == "(" || next == "[" || next == "\"" || next == "_" || next == "."
    }
}
