extension ParseTableCompiler.CompilationResult {
    /// Whether every index in the tables lands inside them, as the parser and lexer assume without checking: a state,
    /// a rule, a lexer state or mode, a token, a step. Tables the compiler builds always are; tables read back from a
    /// cache file may not be, and one bad index would trap on every launch that reads the file. A production's fields
    /// must also come in increasing step order, the order the parser gives a field's nodes.
    ///
    /// - Complexity: O(n) in the size of the tables.
    public var isConsistent: Bool {
        parseTableIsConsistent && lexTable.isConsistent(stateCount: parseTable.stateCount)
            && productions.allSatisfy { production in
                (production.fields.first?.step ?? 0) >= 0
                    && zip(production.fields, production.fields.dropFirst()).allSatisfy { $0.step < $1.step }
                    && production.aliases.keys.allSatisfy { $0 >= 0 }
            }
    }

    private var parseTableIsConsistent: Bool {
        let table = parseTable
        // The count comes first: a range of states is only formed from a positive one, which would otherwise trap.
        guard table.stateCount > 0 else { return false }
        let states = 0 ..< table.stateCount
        guard table.actions.isWellFormed, table.gotos.isWellFormed,
            table.validExternals.isWellFormed, table.actions.stateCount == table.stateCount,
            table.gotos.stateCount == table.stateCount, table.actions.columnCount == table.terminals.count,
            table.gotos.columnCount == table.nonTerminals.count
        else { return false }
        guard table.externalSymbols.count == table.externalNames.count,
            table.externalIsExtra.count == table.externalNames.count,
            table.validExternals.count == table.stateCount,
            table.validExternals.rowsAll(haveCount: table.externalNames.count)
        else { return false }
        return table.actions.shiftsAll(into: states)
            && table.actions.indirectActions.allSatisfy { isValid($0, states: states, nested: false) }
            && table.gotos.targetsAll(in: states)
            && table.lostShifts.allSatisfy { state, shifts in
                states.contains(state)
                    && shifts.allSatisfy { table.terminals.indices.contains($0.key) && states.contains($0.value) }
            }
    }

    /// Whether `action` shifts to one of `states` or reduces by a rule the tables have; a conflict, never `nested` in
    /// another, holds only such actions.
    private func isValid(_ action: Action, states: Range<Int>, nested: Bool) -> Bool {
        switch action {
            case .shift(let target):
                states.contains(target)
            case .reduce(let rule, let count, _):
                productions.indices.contains(rule) && count >= 0
            case .accept, .error:
                true
            case .conflict(let actions):
                !nested && actions.allSatisfy { isValid($0, states: states, nested: true) }
        }
    }
}

extension LexTable {
    /// Whether the automaton's moves, accepted tokens and modes land inside the table, a mode for each of the parse
    /// table's `stateCount` states, and whether the keyword trie's moves do.
    func isConsistent(stateCount: Int) -> Bool {
        let keywordTrieIsConsistent = states.allSatisfy { state in
            state.transitions.allSatisfy { states.indices.contains($0.1) }
        }
        guard !modeStarts.isEmpty else { return keywordTrieIsConsistent && automaton.isEmpty }
        return keywordTrieIsConsistent
            && stateModes.count == stateCount
            && modeStarts.allSatisfy(automaton.indices.contains)
            && stateModes.allSatisfy(modeStarts.indices.contains)
            && modeValidTokens.count == modeStarts.count
            && modeEmptyTokens.count == modeStarts.count
            && modeEmptyAfterSeparator.count == modeStarts.count
            && modeValidTokens.allSatisfy { $0.allSatisfy(tokens.indices.contains) }
            && modeEmptyTokens.allSatisfy { $0.map(tokens.indices.contains) ?? true }
            && modeEmptyAfterSeparator.allSatisfy { $0.map(tokens.indices.contains) ?? true }
            && (wordToken.map(tokens.indices.contains) ?? true)
            && keywordTokens.values.allSatisfy(tokens.indices.contains)
            && (errorMode.map(modeStarts.indices.contains) ?? true)
            && (modeSource.map { $0.isConsistent(tokenCount: tokens.count) } ?? true)
            && automaton.isWellFormed
            && automaton.movesAreConsistent(tokens: tokens.indices)
    }
}

extension LexModeSource {
    /// Whether the token automaton's moves and starts land inside it, and its tokens and priorities are the table's
    /// `tokenCount` tokens.
    func isConsistent(tokenCount: Int) -> Bool {
        let tokens = 0 ..< tokenCount
        return nfa.starts.count == tokenCount && priorities.count == tokenCount
            && nfa.owners.count == nfa.states.count
            && nfa.starts.allSatisfy(nfa.states.indices.contains)
            && nfa.owners.allSatisfy(tokens.contains)
            && nfa.nullableTokens.allSatisfy(tokens.contains)
            && nfa.states.allSatisfy { state in
                switch state {
                    case .advance(_, let next, _, _): nfa.states.indices.contains(next)
                    case .split(let targets): targets.allSatisfy(nfa.states.indices.contains)
                    case .accept(let token, _): tokens.contains(token)
                }
            }
    }
}
