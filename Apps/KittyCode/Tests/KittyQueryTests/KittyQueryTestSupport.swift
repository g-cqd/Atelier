import Testing

@testable import KittyParser
@testable import KittyQuery

enum QueryPatternExpectationError: Error {
    case expectedAlternation
    case expectedDirectivePredicate
    case expectedEqPredicate
    case expectedLiteral
    case expectedMatchPredicate
    case expectedNodeMatch
    case expectedQuantified
    case expectedSequence
    case expectedWildcard
}

func requireAlternation(_ pattern: QueryPattern) throws -> [QueryPattern] {
    guard case .alternation(let alternatives) = pattern else {
        throw QueryPatternExpectationError.expectedAlternation
    }
    return alternatives
}

func requireDirectivePredicate(_ pattern: QueryPattern) throws -> (
    name: String, arguments: [String]
) {
    guard case .predicate(.directive(name: let name, arguments: let arguments)) = pattern else {
        throw QueryPatternExpectationError.expectedDirectivePredicate
    }
    return (name, arguments)
}

func requireEqPredicate(_ pattern: QueryPattern) throws -> (capture: String, value: String)
{
    guard case .predicate(.eq(capture: let capture, value: let value)) = pattern else {
        throw QueryPatternExpectationError.expectedEqPredicate
    }
    return (capture, value)
}

func requireLiteral(_ pattern: QueryPattern) throws -> (value: String, capture: String?) {
    guard case .literal(let value, let capture) = pattern else {
        throw QueryPatternExpectationError.expectedLiteral
    }
    return (value, capture)
}

func requireMatchPredicate(_ pattern: QueryPattern) throws -> (
    capture: String, pattern: String
) {
    guard case .predicate(.match(capture: let capture, pattern: let matchedPattern)) = pattern
    else {
        throw QueryPatternExpectationError.expectedMatchPredicate
    }
    return (capture, matchedPattern)
}

func requireNodeMatch(_ pattern: QueryPattern) throws -> (type: String, capture: String?) {
    guard case .nodeMatch(let type, _, let capture) = pattern else {
        throw QueryPatternExpectationError.expectedNodeMatch
    }
    return (type, capture)
}

func requireSequence(_ pattern: QueryPattern) throws -> [QueryPattern] {
    guard case .sequence(let patterns) = pattern else {
        throw QueryPatternExpectationError.expectedSequence
    }
    return patterns
}

func requireQuantified(_ pattern: QueryPattern) throws -> (pattern: QueryPattern, quantifier: Quantifier) {
    guard case .quantified(let inner, let quantifier) = pattern else {
        throw QueryPatternExpectationError.expectedQuantified
    }
    return (inner, quantifier)
}

func requireWildcard(_ pattern: QueryPattern) throws -> String? {
    guard case .wildcard(let capture) = pattern else {
        throw QueryPatternExpectationError.expectedWildcard
    }
    return capture
}
