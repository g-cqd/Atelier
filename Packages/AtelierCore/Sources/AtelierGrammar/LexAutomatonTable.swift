/// The lexer's deterministic automaton, kept small: a state's moves are grouped by where they go, and each group reads
/// a set of scalar ranges that the automaton stores once however many groups read it.
///
/// A grammar whose identifiers take Unicode letters has hundreds of states that each read the same few hundred ranges
/// of letters, so its moves, a million and more one by one, come to a few hundred sets.
///
/// A collection of ``LexAutomatonState`` values, each built from its groups when read; the lexer reads the groups.
public struct LexAutomaton: Sendable, RandomAccessCollection {
    /// A state's moves to one target: the scalars of ``set`` go to ``target``, as separators when ``skips``.
    struct Group: Sendable, Equatable {
        var set: UInt32
        var skips: Bool
        var target: Int
    }

    /// Each state's accepted token.
    private(set) var accepts: [Int?]
    /// Where each state's groups start in ``groups``, and where the last state's end: one more than the states.
    private(set) var groupStarts: [UInt32]
    private(set) var groups: [Group]
    /// Where each set's ranges start in ``bounds``, in pairs, and where the last set's end: one more than the sets.
    private(set) var setStarts: [UInt32]
    /// The sets' ranges, each a lower and an upper bound, in the order their state read them.
    private(set) var bounds: [UInt32]

    /// The automaton of `states`, whose moves each are sorted by scalar and disjoint.
    public init(_ states: [LexAutomatonState] = []) {
        self.init(accepts: [], groupStarts: [0], groups: [], setStarts: [0], bounds: [])
        var setIndex: [[UInt32]: UInt32] = [:]
        accepts.reserveCapacity(states.count)
        groupStarts.reserveCapacity(states.count + 1)
        for state in states {
            accepts.append(state.accept)
            // The groups in the order of their first move, each move in its group in the state's order. Moves come
            // in runs to one target, so only a move that leaves the last move's group looks its group up.
            var keys: [GroupKey] = []
            var members: [[UInt32]] = []
            var groupOfKey: [GroupKey: Int] = [:]
            var last = 0
            for move in state.transitions {
                let key = GroupKey(target: move.target, skips: move.skips)
                if last >= keys.count || keys[last] != key {
                    if let found = groupOfKey[key] {
                        last = found
                    } else {
                        last = keys.count
                        groupOfKey[key] = last
                        keys.append(key)
                        members.append([])
                    }
                }
                members[last].append(move.lower)
                members[last].append(move.upper)
            }
            for (key, ranges) in zip(keys, members) {
                let set: UInt32
                if let existing = setIndex[ranges] {
                    set = existing
                } else {
                    set = UInt32(setStarts.count - 1)
                    setIndex[ranges] = set
                    bounds.append(contentsOf: ranges)
                    setStarts.append(UInt32(bounds.count / 2))
                }
                groups.append(Group(set: set, skips: key.skips, target: key.target))
            }
            groupStarts.append(UInt32(groups.count))
        }
    }

    private struct GroupKey: Hashable {
        var target: Int
        var skips: Bool
    }

    /// The automaton made of its parts, as a cache file's reader checked them.
    init(accepts: [Int?], groupStarts: [UInt32], groups: [Group], setStarts: [UInt32], bounds: [UInt32]) {
        self.accepts = accepts
        self.groupStarts = groupStarts
        self.groups = groups
        self.setStarts = setStarts
        self.bounds = bounds
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { accepts.count }

    /// State `state` with its moves sorted by scalar, built from its groups.
    /// - Complexity: O(m log m) in its moves: for tests and diagnostics, not for lexing.
    public subscript(state: Int) -> LexAutomatonState {
        var moves: [LexTransition] = []
        for group in groups(of: state) {
            forEachRange(of: group.set) { lower, upper in
                moves.append(LexTransition(lower: lower, upper: upper, target: group.target, skips: group.skips))
                return true
            }
        }
        moves.sort { $0.lower < $1.lower }
        return LexAutomatonState(transitions: moves, accept: accepts[state])
    }

    /// The token `state` accepts, if the lexer stops there.
    public func accept(of state: Int) -> Int? {
        accepts[state]
    }

    /// The move of `state` on `scalar`, where the lexer goes and whether the scalar is a separator; nil for none.
    /// - Complexity: O(g log r) for the state's g groups of up to r ranges each.
    public func move(from state: Int, on scalar: UInt32) -> (target: Int, skips: Bool)? {
        for group in groups(of: state) where contains(scalar, inSet: group.set) {
            return (group.target, group.skips)
        }
        return nil
    }

    /// Calls `body` with each move of `state` that reads a scalar below `limit`, in no particular order, clipped to
    /// `limit`: for a lexer to lay out its direct table of the moves on ASCII.
    public func forEachMove(
        from state: Int, below limit: UInt32,
        _ body: (_ lower: UInt32, _ upper: UInt32, _ target: Int, _ skips: Bool)
            -> Void
    ) {
        for group in groups(of: state) {
            forEachRange(of: group.set) { lower, upper in
                guard lower < limit else { return false }
                body(lower, Swift.min(upper, limit - 1), group.target, group.skips)
                return true
            }
        }
    }

    func groups(of state: Int) -> ArraySlice<Group> {
        groups[Int(groupStarts[state]) ..< Int(groupStarts[state + 1])]
    }

    /// The number of sets.
    var setCount: Int { setStarts.count - 1 }

    /// Calls `body` with each range of `set` in order, until it returns false.
    func forEachRange(of set: UInt32, _ body: (_ lower: UInt32, _ upper: UInt32) -> Bool) {
        let start = Int(setStarts[Int(set)])
        let end = Int(setStarts[Int(set) + 1])
        for pair in start ..< end where !body(bounds[2 * pair], bounds[2 * pair + 1]) {
            return
        }
    }

    /// Whether a range of `set`, sorted and disjoint, holds `scalar`.
    private func contains(_ scalar: UInt32, inSet set: UInt32) -> Bool {
        var low = Int(setStarts[Int(set)])
        var high = Int(setStarts[Int(set) + 1])
        while low < high {
            let middle = (low + high) / 2
            if bounds[2 * middle + 1] < scalar {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < Int(setStarts[Int(set) + 1]) && bounds[2 * low] <= scalar
    }
}

extension LexAutomaton: Equatable {
    /// Whether both automata have the same states, however they store them.
    public static func == (lhs: LexAutomaton, rhs: LexAutomaton) -> Bool {
        if lhs.accepts == rhs.accepts, lhs.groupStarts == rhs.groupStarts, lhs.groups == rhs.groups,
            lhs.setStarts == rhs.setStarts, lhs.bounds == rhs.bounds
        {
            return true
        }
        return lhs.elementsEqual(rhs)
    }
}

extension LexAutomaton: Codable {
    /// An automaton encodes as its states, each with its moves, as the tables' JSON always has.
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([LexAutomatonState].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Array(self))
    }
}

extension LexAutomaton {
    /// Whether every read of the automaton lands inside it: each state's groups, each group's set and each set's
    /// ranges exist. An automaton built from states always is; one read back from a file may not be.
    /// - Complexity: O(n) in the states, groups and sets.
    var isWellFormed: Bool {
        guard groupStarts.count == accepts.count + 1, groupStarts.first == 0, groupStarts.last == UInt32(groups.count),
            setStarts.first == 0, Int(setStarts.last ?? 1) * 2 == bounds.count
        else { return false }
        return zip(groupStarts, groupStarts.dropFirst()).allSatisfy { $0 <= $1 }
            && zip(setStarts, setStarts.dropFirst()).allSatisfy { $0 <= $1 }
            && groups.allSatisfy { Int($0.set) < setCount }
    }

    /// Whether every move goes to a state of the automaton, every accepted token is one of `tokens`, and each set's
    /// ranges are sorted, disjoint, non-empty and within Unicode.
    ///
    /// Two groups of one state that read the same scalar go unnoticed: the lexer takes the first, and the compiler
    /// never builds such a state.
    /// - Complexity: O(n) in the states, groups and stored ranges.
    func movesAreConsistent(tokens: Range<Int>) -> Bool {
        guard accepts.allSatisfy({ $0.map(tokens.contains) ?? true }),
            groups.allSatisfy({ indices.contains($0.target) })
        else { return false }
        return (0 ..< setCount)
            .allSatisfy { set in
                var next: UInt32 = 0
                var isSorted = true
                forEachRange(of: UInt32(set)) { lower, upper in
                    isSorted = next <= lower && lower <= upper && upper <= ScalarRanges.maxScalar
                    next = upper &+ 1
                    return isSorted
                }
                return isSorted
            }
    }
}
