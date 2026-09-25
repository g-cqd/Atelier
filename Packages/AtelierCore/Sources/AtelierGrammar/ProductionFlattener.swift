/// How a production groups with itself when a shift competes with its reduction at equal precedence.
enum Associativity: Sendable, Equatable {
    /// `prec.left`: reduce, so `a - b - c` groups as `(a - b) - c`.
    case left
    /// `prec.right`: shift, so `a = b = c` groups as `a = (b = c)`.
    case right
}

/// One symbol of a flattened production, with the metadata in scope where the grammar writes it.
struct FlatStep: Sendable, Equatable {
    var symbol: String
    /// The precedence of the innermost `prec` around both this step and the next, or around this step when it ends
    /// the production: the precedence an LR item with its dot right after this step has. 0 without one.
    var precedence: Precedence = 0
    /// The associativity that goes with `precedence`.
    var associativity: Associativity?
    var alias: SymbolAlias?
    var field: String?
}

/// A grammar rule's alternative with every choice, repetition and wrapper expanded away: a plain sequence of symbols.
struct FlatProduction: Sendable, Equatable {
    var name: String
    var steps: [FlatStep]
    /// The `prec.dynamic` value of the production, the one of largest magnitude it lies in: a parse that reduces it
    /// wins over an equally good parse that does not, by that much.
    var dynamicPrecedence = 0

    var symbols: [String] { steps.map(\.symbol) }

    /// The fields of the steps, in step order.
    var fields: [ProductionField] {
        steps.indices.compactMap { index in steps[index].field.map { ProductionField(step: index, name: $0) } }
    }

    var aliases: [Int: SymbolAlias] {
        var aliases: [Int: SymbolAlias] = [:]
        for (index, step) in steps.enumerated() {
            if let alias = step.alias { aliases[index] = alias }
        }
        return aliases
    }
}

/// Flattens a grammar's syntactic rules, those of a ``LexicalGrammar``, into productions the way tree-sitter does,
/// keeping on each step the precedence, associativity, alias and field in scope: the first two to resolve conflicts
/// as tree-sitter does, the others to name the step's node.
///
/// A repetition becomes a left-recursive helper rule, `_repeat1_n → x | _repeat1_n x`, whose steps start with no
/// metadata, as the helper rules tree-sitter builds do, and a repetition that may be empty the choice of that helper or
/// nothing, as tree-sitter reads `repeat(x)`.
struct ProductionFlattener {
    /// The metadata in scope at a point of a rule.
    private struct Scope {
        var precedence: Precedence = 0
        var associativity: Associativity?
        var alias: SymbolAlias?
        var field: String?

        func step(_ symbol: String) -> FlatStep {
            FlatStep(symbol: symbol, precedence: precedence, associativity: associativity, alias: alias, field: field)
        }
    }

    /// A sequence of steps one alternative of a rule expands to.
    private struct FlatSequence {
        var steps: [FlatStep]
        var dynamicPrecedence = 0

        static let empty = FlatSequence(steps: [])

        /// `self` followed by `other`; of two dynamic precedences, the one of larger magnitude wins, the first on a tie.
        func appending(_ other: FlatSequence) -> FlatSequence {
            FlatSequence(
                steps: steps + other.steps,
                dynamicPrecedence: abs(other.dynamicPrecedence) > abs(dynamicPrecedence)
                    ? other.dynamicPrecedence : dynamicPrecedence)
        }
    }

    private let limits: GrammarCompilationLimits
    private var auxiliaryProductions: [FlatProduction] = []
    private var counter = 0
    private var productionCount = 0
    private var productionSymbolCount = 0

    private init(limits: GrammarCompilationLimits) {
        self.limits = limits
    }

    /// The productions of `rules`, first the augmented start `_start → <first rule>`, then each rule's alternatives
    /// in order, then the helper rules of repetitions.
    /// - Throws: `GrammarError.resourceLimitExceeded` when the expansion passes one of `limits`.
    static func flatten(
        _ rules: [(name: String, rule: Rule)],
        limits: GrammarCompilationLimits
    ) throws(GrammarError) -> [FlatProduction] {
        var flattener = ProductionFlattener(limits: limits)
        var productions: [FlatProduction] = []
        if let first = rules.first {
            let start = FlatProduction(name: "_start", steps: [FlatStep(symbol: first.name)])
            try flattener.register(start)
            productions.append(start)
        }
        for (name, rule) in rules {
            for sequence in try flattener.expand(rule, ruleName: name, scope: Scope(), atEnd: true) {
                let production = FlatProduction(
                    name: name, steps: sequence.steps, dynamicPrecedence: sequence.dynamicPrecedence)
                try flattener.register(production)
                productions.append(production)
            }
        }
        productions.append(contentsOf: flattener.auxiliaryProductions)
        return productions
    }

    // MARK: - Expansion

    /// The alternatives `rule` expands to under `scope`; `atEnd` says whether they end the production.
    private mutating func expand(
        _ rule: Rule,
        ruleName: String,
        scope: Scope,
        atEnd: Bool
    ) throws(GrammarError) -> [FlatSequence] {
        switch rule {
            case .symbol(let name):
                return [FlatSequence(steps: [scope.step(name)])]
            case .string, .pattern, .token, .immediateToken:
                throw .invalidRuleType("A lexical rule in \(ruleName) is not a token's symbol")
            case .blank:
                return [.empty]
            case .seq(let members):
                return try expandSequence(members, ruleName: ruleName, scope: scope, atEnd: atEnd)
            case .choice(let members):
                return try expandChoice(members, ruleName: ruleName, scope: scope, atEnd: atEnd)
            case .optional(let content):
                let expanded = try expand(content, ruleName: ruleName, scope: scope, atEnd: atEnd)
                let alternativeCount = try checkedAlternativeCount(
                    lhs: expanded.count, rhs: 1, operation: { $0.addingReportingOverflow($1) },
                    construct: "Optional", ruleName: ruleName)
                try ensureAlternativeCount(alternativeCount, construct: "Optional", ruleName: ruleName)
                return [FlatSequence.empty] + expanded
            case .repeat(let content):
                // As tree-sitter reads it: once or more, or not at all. A helper deriving the empty string would have
                // the parser reduce it before the first item, a reduction no precedence of the rule around it orders.
                return [
                    FlatSequence(steps: [scope.step(try repetition(of: content, ruleName: ruleName))]), .empty
                ]
            case .repeat1(let content):
                return [FlatSequence(steps: [scope.step(try repetition(of: content, ruleName: ruleName))])]
            case .prec(let value, let content):
                var inner = scope
                inner.precedence = value
                return try expandScoped(content, ruleName: ruleName, inner: inner, outer: scope, atEnd: atEnd)
            case .precLeft(let value, let content), .precRight(let value, let content):
                var inner = scope
                inner.precedence = value
                inner.associativity = if case .precLeft = rule { .left } else { .right }
                return try expandScoped(content, ruleName: ruleName, inner: inner, outer: scope, atEnd: atEnd)
            case .precDynamic(let value, let content):
                return try expand(content, ruleName: ruleName, scope: scope, atEnd: atEnd)
                    .map { sequence in
                        var sequence = sequence
                        if abs(sequence.dynamicPrecedence) <= abs(value) { sequence.dynamicPrecedence = value }
                        return sequence
                    }
            case .field(let name, let content):
                var inner = scope
                inner.field = name
                return try expand(content, ruleName: ruleName, scope: inner, atEnd: atEnd)
            case .alias(let content, let value, let isNamed):
                var inner = scope
                inner.alias = SymbolAlias(type: isNamed ? value : "\"" + value + "\"", isNamed: isNamed)
                return try expand(content, ruleName: ruleName, scope: inner, atEnd: atEnd)
        }
    }

    /// `content` expanded under `inner`, a precedence scope inside `outer`. When the scope ends before the production
    /// does, its last step takes the precedence and associativity of `outer`: an item with its dot there has left
    /// the scope.
    private mutating func expandScoped(
        _ content: Rule,
        ruleName: String,
        inner: Scope,
        outer: Scope,
        atEnd: Bool
    ) throws(GrammarError) -> [FlatSequence] {
        var sequences = try expand(content, ruleName: ruleName, scope: inner, atEnd: atEnd)
        guard !atEnd else { return sequences }
        for index in sequences.indices {
            guard let last = sequences[index].steps.indices.last else { continue }
            sequences[index].steps[last].precedence = outer.precedence
            sequences[index].steps[last].associativity = outer.associativity
        }
        return sequences
    }

    private mutating func expandSequence(
        _ members: [Rule],
        ruleName: String,
        scope: Scope,
        atEnd: Bool
    ) throws(GrammarError) -> [FlatSequence] {
        var result = [FlatSequence.empty]
        for (offset, member) in members.enumerated() {
            let memberExpanded = try expand(
                member, ruleName: ruleName, scope: scope, atEnd: atEnd && offset == members.count - 1)
            let alternativeCount = try checkedAlternativeCount(
                lhs: result.count, rhs: memberExpanded.count, operation: { $0.multipliedReportingOverflow(by: $1) },
                construct: "Sequence", ruleName: ruleName)
            try ensureAlternativeCount(alternativeCount, construct: "Sequence", ruleName: ruleName)
            var combined: [FlatSequence] = []
            combined.reserveCapacity(alternativeCount)
            for existing in result {
                for expanded in memberExpanded {
                    combined.append(existing.appending(expanded))
                }
            }
            result = combined
        }
        return result
    }

    private mutating func expandChoice(
        _ members: [Rule],
        ruleName: String,
        scope: Scope,
        atEnd: Bool
    ) throws(GrammarError) -> [FlatSequence] {
        var alternatives: [FlatSequence] = []
        for member in members {
            let expanded = try expand(member, ruleName: ruleName, scope: scope, atEnd: atEnd)
            let alternativeCount = try checkedAlternativeCount(
                lhs: alternatives.count, rhs: expanded.count, operation: { $0.addingReportingOverflow($1) },
                construct: "Choice", ruleName: ruleName)
            try ensureAlternativeCount(alternativeCount, construct: "Choice", ruleName: ruleName)
            alternatives.append(contentsOf: expanded)
        }
        return alternatives
    }

    /// The name of a new helper rule matching `content` repeated once or more. Its steps start with no metadata: what
    /// surrounds the repetition applies to the helper's step.
    private mutating func repetition(of content: Rule, ruleName: String) throws(GrammarError) -> String {
        counter += 1
        let helper = "_repeat1_\(counter)"
        let inner = try expand(content, ruleName: ruleName, scope: Scope(), atEnd: true)
        for alternative in inner {
            try appendAuxiliary(
                FlatProduction(
                    name: helper, steps: alternative.steps, dynamicPrecedence: alternative.dynamicPrecedence))
        }
        // An empty alternative would make `helper → helper`, a cycle that matches nothing new.
        for alternative in inner where !alternative.steps.isEmpty {
            try appendAuxiliary(
                FlatProduction(
                    name: helper,
                    steps: [FlatStep(symbol: helper)] + alternative.steps,
                    dynamicPrecedence: alternative.dynamicPrecedence))
        }
        return helper
    }

    // MARK: - Limits

    private mutating func register(_ production: FlatProduction) throws(GrammarError) {
        productionCount += 1
        guard productionCount <= limits.maxFlattenedProductions else {
            throw .resourceLimitExceeded(
                "Flattened grammar exceeded limit (\(productionCount) productions, limit \(limits.maxFlattenedProductions))"
            )
        }

        productionSymbolCount += production.steps.count
        guard productionSymbolCount <= limits.maxProductionSymbols else {
            throw .resourceLimitExceeded(
                "Flattened grammar symbol count exceeded limit (\(productionSymbolCount) symbols, limit \(limits.maxProductionSymbols))"
            )
        }
    }

    private mutating func appendAuxiliary(_ production: FlatProduction) throws(GrammarError) {
        try register(production)
        auxiliaryProductions.append(production)
    }

    private func ensureAlternativeCount(_ count: Int, construct: String, ruleName: String) throws(GrammarError) {
        guard count <= limits.maxExpandedAlternativesPerRule else {
            throw .resourceLimitExceeded(
                "\(construct) expansion for \(ruleName) exceeded limit (\(count) alternatives, limit \(limits.maxExpandedAlternativesPerRule))"
            )
        }
    }

    private func checkedAlternativeCount(
        lhs: Int,
        rhs: Int,
        operation: (Int, Int) -> (partialValue: Int, overflow: Bool),
        construct: String,
        ruleName: String
    ) throws(GrammarError) -> Int {
        let (count, overflowed) = operation(lhs, rhs)
        guard !overflowed else {
            throw .resourceLimitExceeded(
                "\(construct) expansion for \(ruleName) exceeded limit (overflow while counting alternatives, limit \(limits.maxExpandedAlternativesPerRule))"
            )
        }
        return count
    }
}
