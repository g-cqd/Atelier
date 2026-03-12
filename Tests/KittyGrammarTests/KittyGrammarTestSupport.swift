import Foundation
import Testing

@testable import KittyGrammar

enum GrammarRuleExpectationError: Error {
    case expectedStringRule
}

func requireStringRule(_ rule: Rule?) throws -> String {
    guard case .some(.string(let value)) = rule else {
        throw GrammarRuleExpectationError.expectedStringRule
    }
    return value
}
