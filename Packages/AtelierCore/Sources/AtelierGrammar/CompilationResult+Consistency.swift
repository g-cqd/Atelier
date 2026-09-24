extension ParseTableCompiler.CompilationResult {
    /// Whether every index in the tables lands inside them, as the parser and lexer assume without checking: a state,
    /// a rule, a lexer state or mode, a token, a step. Tables the compiler builds always are; tables read back from a
    /// cache file may not be, and one bad index would trap on every launch that reads the file.
    ///
    /// - Complexity: O(n) in the size of the tables.
    public var isConsistent: Bool {
        parseTableIsConsistent && lexTable.isConsistent(stateCount: parseTable.stateCount)
            && productions.allSatisfy { production in
                production.fields.keys.allSatisfy { $0 >= 0 } && production.aliases.keys.allSatisfy { $0 >= 0 }
            }
    }

    private var parseTableIsConsistent: Bool {
        let table = parseTable
        let states = 0 ..< table.stateCount
        guard table.stateCount > 0, table.actions.count == table.stateCount, table.gotos.count == table.stateCount
        else { return false }
        guard table.externalSymbols.count == table.externalNames.count,
            table.externalIsExtra.count == table.externalNames.count,
            table.validExternals.count == table.stateCount,
            table.validExternals.allSatisfy({ $0.count == table.externalNames.count })
        else { return false }
        return table.actions.allSatisfy { row in
            row.count == table.terminals.count && row.allSatisfy { isValid($0, states: states, nested: false) }
        }
            && table.gotos.allSatisfy { row in
                row.count == table.nonTerminals.count && row.allSatisfy { $0.map(states.contains) ?? true }
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
            && automaton.allSatisfy { state in
                (state.accept.map(tokens.indices.contains) ?? true) && movesAreConsistent(state.transitions)
            }
    }

    /// Whether `moves` read scalars in order, on non-empty ranges that do not overlap, into states of the automaton.
    private func movesAreConsistent(_ moves: [LexTransition]) -> Bool {
        var next: UInt32 = 0
        for move in moves {
            guard next <= move.lower, move.lower <= move.upper, move.upper <= ScalarRanges.maxScalar,
                automaton.indices.contains(move.target)
            else { return false }
            next = move.upper + 1
        }
        return true
    }
}
