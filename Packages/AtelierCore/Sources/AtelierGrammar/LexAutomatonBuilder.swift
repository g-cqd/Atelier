/// Builds the lexer's deterministic automaton from a ``TokenNFA`` the way tree-sitter builds its lex table: a start
/// state per lex mode, the states reachable from them shared between modes, and tree-sitter's rules for choosing
/// between tokens.
///
/// Where several tokens could end, the one of higher completion precedence wins, then the one of higher implicit
/// precedence (a string over a pattern), then the one defined first. The automaton reads on past a completed token
/// only for a token of at least the same precedence, and at equal precedence not along a separator, nor into
/// another token when a separator could also be read; otherwise the longest match wins.
struct LexAutomatonBuilder {
    /// The most states an automaton may have.
    static let maxStates = 50_000

    private let nfa: TokenNFA
    private let tokens: [LexTokenPriority]
    private(set) var states: [LexAutomatonState] = []
    private struct StateKey: Hashable {
        var nfaStates: [Int]
        var hasReadTokenScalar: Bool
    }
    private var stateIDs: [StateKey: Int] = [:]
    private var unpopulated: [(id: Int, key: StateKey)] = []
    /// Each state's key, and whether its accepted token and moves are set yet.
    private var keys: [StateKey] = []
    private var populated: [Bool] = []

    init(nfa: TokenNFA, tokens: [LexTokenPriority]) {
        self.nfa = nfa
        self.tokens = tokens
    }

    /// The start state of the mode in which the tokens at `validTokens` are valid, with every state it reaches.
    /// - Throws: `GrammarError.resourceLimitExceeded` past ``maxStates``.
    mutating func startState(for validTokens: [Int]) throws(GrammarError) -> Int {
        let start = try lazyStartState(for: validTokens)
        while let (id, key) = unpopulated.popLast() {
            try populate(id, key: key)
        }
        return start
    }

    /// The start state of the mode in which the tokens at `validTokens` are valid, set up alone: ``populated(_:)``
    /// sets up each other state the first time it is asked for, so a mode read a few times builds only the states
    /// those reads reach.
    mutating func lazyStartState(for validTokens: [Int]) throws(GrammarError) -> Int {
        let start = try state(for: nfa.closure(of: validTokens.map { nfa.starts[$0] }), hasReadTokenScalar: false)
        try populate(start, key: keys[start])
        return start
    }

    /// State `id` with its accepted token and moves, set up now if they were not yet.
    /// - Throws: `GrammarError.resourceLimitExceeded` past ``maxStates``.
    mutating func populated(_ id: Int) throws(GrammarError) -> LexAutomatonState {
        if !populated[id] { try populate(id, key: keys[id]) }
        return states[id]
    }

    private mutating func state(for nfaStates: [Int], hasReadTokenScalar: Bool) throws(GrammarError) -> Int {
        let key = StateKey(nfaStates: nfaStates, hasReadTokenScalar: hasReadTokenScalar)
        if let id = stateIDs[key] {
            return id
        }
        guard states.count < Self.maxStates else {
            throw .resourceLimitExceeded("Lexer automaton exceeded limit (\(Self.maxStates) states)")
        }
        let id = states.count
        states.append(LexAutomatonState(transitions: [], accept: nil))
        stateIDs[key] = id
        keys.append(key)
        populated.append(false)
        unpopulated.append((id, key))
        return id
    }

    private mutating func populate(_ id: Int, key: StateKey) throws(GrammarError) {
        guard !populated[id] else { return }
        populated[id] = true
        var completion: Completion?
        var hasSeparator = false
        for nfaState in key.nfaStates {
            switch nfa.states[nfaState] {
                case .accept(let token, let precedence):
                    if !key.hasReadTokenScalar && nfa.nullableTokens.contains(token) { continue }
                    let candidate = Completion(token: token, precedence: precedence)
                    if let current = completion, prefers(current, over: candidate) { continue }
                    completion = candidate
                case .advance(_, _, _, let isSeparator):
                    hasSeparator = hasSeparator || isSeparator
                case .split:
                    break
            }
        }

        var transitions: [LexTransition] = []
        for group in transitionGroups(of: key.nfaStates) {
            if let completion, !prefers(group, over: completion, hasSeparator: hasSeparator) { continue }
            let target = try state(
                for: nfa.closure(of: group.targets), hasReadTokenScalar: !group.isSeparator)
            for range in group.characters.ranges {
                transitions.append(
                    LexTransition(
                        lower: range.lowerBound, upper: range.upperBound, target: target, skips: group.isSeparator))
            }
        }
        transitions.sort { $0.lower < $1.lower }
        states[id] = LexAutomatonState(transitions: transitions, accept: completion?.token)
    }

    // MARK: - Choosing between tokens

    /// A token that can end at a state, with the precedence it completes with.
    private struct Completion {
        var token: Int
        var precedence: Int
    }

    /// Whether `current` stays the token that ends here when `candidate` could end too.
    private func prefers(_ current: Completion, over candidate: Completion) -> Bool {
        if current.precedence != candidate.precedence {
            return current.precedence > candidate.precedence
        }
        let currentImplicit = tokens[current.token].implicitPrecedence
        let candidateImplicit = tokens[candidate.token].implicitPrecedence
        if currentImplicit != candidateImplicit {
            return currentImplicit > candidateImplicit
        }
        return current.token < candidate.token
    }

    /// Whether the automaton reads on along `group` rather than stop at `completion`.
    private func prefers(_ group: TransitionGroup, over completion: Completion, hasSeparator: Bool) -> Bool {
        if group.precedence != completion.precedence {
            return group.precedence > completion.precedence
        }
        return !group.isSeparator && (!hasSeparator || group.owners.contains(completion.token))
    }

    // MARK: - Transitions

    /// The moves out of a state on the scalars of `characters`, merged from the automaton states that read them.
    private struct TransitionGroup {
        var characters: ScalarRanges
        /// The states the moves lead to.
        var targets: [Int]
        /// Whether every move is a separator's: a scalar read so is left out of the token.
        var isSeparator: Bool
        /// The highest precedence of the moves.
        var precedence: Int
        /// The tokens the moves belong to.
        var owners: Set<Int>
    }

    /// The moves out of `nfaStates`, grouped so each group's scalars are read by the same automaton states.
    private func transitionGroups(of nfaStates: [Int]) -> [TransitionGroup] {
        // Every range's start and end, where the set of states that read a scalar changes.
        var boundaries: [(position: UInt32, state: Int, opens: Bool)] = []
        for nfaState in nfaStates {
            guard case .advance(let characters, _, _, _) = nfa.states[nfaState] else { continue }
            for range in characters.ranges {
                boundaries.append((range.lowerBound, nfaState, true))
                boundaries.append((range.upperBound + 1, nfaState, false))
            }
        }
        boundaries.sort { $0.position < $1.position }

        // The scalar ranges each set of reading states reads, the sets in the order their first range comes.
        var readerSets: [[Int]] = []
        var rangesByReaders: [[Int]: [ClosedRange<UInt32>]] = [:]
        var reading = Set<Int>()
        var index = 0
        while index < boundaries.count {
            let position = boundaries[index].position
            while index < boundaries.count, boundaries[index].position == position {
                if boundaries[index].opens {
                    reading.insert(boundaries[index].state)
                } else {
                    reading.remove(boundaries[index].state)
                }
                index += 1
            }
            guard !reading.isEmpty, index < boundaries.count else { continue }
            let readers = reading.sorted()
            if rangesByReaders[readers] == nil {
                readerSets.append(readers)
            }
            rangesByReaders[readers, default: []].append(position ... boundaries[index].position - 1)
        }
        return readerSets.map { readers in group(of: readers, over: ScalarRanges(rangesByReaders[readers] ?? [])) }
    }

    private func group(of readers: [Int], over characters: ScalarRanges) -> TransitionGroup {
        var group = TransitionGroup(
            characters: characters, targets: [], isSeparator: true, precedence: Int.min, owners: [])
        var targets = Set<Int>()
        for reader in readers {
            guard case .advance(_, let next, let precedence, let isSeparator) = nfa.states[reader] else { continue }
            targets.insert(next)
            group.isSeparator = group.isSeparator && isSeparator
            group.precedence = max(group.precedence, precedence)
            group.owners.insert(nfa.owners[reader])
        }
        group.targets = targets.sorted()
        return group
    }
}
