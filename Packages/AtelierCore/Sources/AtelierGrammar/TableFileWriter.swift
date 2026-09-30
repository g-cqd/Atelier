import Foundation

/// Writes tables into a table file (``TableFile``): each part in the order ``TableFileReader`` reads it, every string
/// as its index in the file's list of strings.
struct TableFileWriter {
    private var body: [UInt8] = []
    private var stringTable: [String] = []
    private var stringIndex: [String: UInt32] = [:]

    /// The file: the header for `version`, the strings, then what was written.
    func file(version: Int) -> Data {
        var payload: [UInt8] = []
        Self.append(UInt32(stringTable.count), to: &payload)
        for string in stringTable {
            Self.append(UInt32(string.utf8.count), to: &payload)
            payload.append(contentsOf: string.utf8)
        }
        payload.append(contentsOf: body)
        var file = TableFile.magic
        Self.append(UInt32(version), to: &file)
        Self.append(UInt32(0), to: &file)
        Self.append(UInt64(payload.count), to: &file)
        Self.append(payload.withUnsafeBytes(TableFile.checksum(of:)), to: &file)
        file.append(contentsOf: payload)
        return Data(file)
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to buffer: inout [UInt8]) {
        withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
    }

    // MARK: - Values

    mutating func u8(_ value: UInt8) { body.append(value) }
    mutating func u32(_ value: UInt32) { Self.append(value, to: &body) }
    mutating func count(_ value: Int) { Self.append(UInt32(value), to: &body) }
    mutating func int(_ value: Int) { Self.append(Int64(value), to: &body) }
    mutating func bool(_ value: Bool) { body.append(value ? 1 : 0) }

    mutating func optionalInt(_ value: Int?) {
        bool(value != nil)
        int(value ?? 0)
    }

    mutating func string(_ value: String) {
        if let index = stringIndex[value] {
            u32(index)
            return
        }
        let index = UInt32(stringTable.count)
        stringIndex[value] = index
        stringTable.append(value)
        u32(index)
    }

    mutating func strings(_ values: [String]) {
        count(values.count)
        values.forEach { string($0) }
    }

    mutating func ints(_ values: [Int]) {
        count(values.count)
        values.forEach { int($0) }
    }

    mutating func bools(_ values: [Bool]) {
        count(values.count)
        values.forEach { bool($0) }
    }

    /// `values` with no count before them: the reader knows how many from what it read before.
    mutating func rawU32s(_ values: [UInt32]) {
        #if _endian(little)
            values.withUnsafeBytes { body.append(contentsOf: $0) }
        #else
            values.forEach { u32($0) }
        #endif
    }

    // MARK: - Tables

    mutating func write(_ result: ParseTableCompiler.CompilationResult) {
        write(result.parseTable)
        write(result.lexTable)
        count(result.productions.count)
        result.productions.forEach { write($0) }
    }

    private mutating func write(_ table: ParseTable) {
        int(table.stateCount)
        strings(table.symbols)
        strings(table.terminals)
        strings(table.nonTerminals)
        write(table.actions)
        write(table.gotos)
        strings(table.externalNames)
        strings(table.externalSymbols)
        count(table.validExternals.distinctRows.count)
        table.validExternals.distinctRows.forEach { bools($0) }
        count(table.validExternals.rowOfState.count)
        rawU32s(table.validExternals.rowOfState)
        bools(table.externalIsExtra)
        count(table.lostShifts.count)
        for (state, shifts) in table.lostShifts.sorted(by: { $0.key < $1.key }) {
            int(state)
            count(shifts.count)
            for (terminal, target) in shifts.sorted(by: { $0.key < $1.key }) {
                int(terminal)
                int(target)
            }
        }
    }

    private mutating func write(_ actions: ParseActionTable) {
        count(actions.columnCount)
        count(actions.rowCount)
        count(actions.rowOfState.count)
        rawU32s(actions.rowOfState)
        rawU32s(actions.cells)
        count(actions.indirectActions.count)
        actions.indirectActions.forEach { write($0) }
    }

    private mutating func write(_ action: Action) {
        switch action {
            case .shift(let state):
                u8(0)
                int(state)
            case .reduce(let rule, let count, let nonTerminal):
                u8(1)
                int(rule)
                int(count)
                string(nonTerminal)
            case .accept:
                u8(2)
            case .error:
                u8(3)
            case .conflict(let actions):
                u8(4)
                count(actions.count)
                actions.forEach { write($0) }
        }
    }

    private mutating func write(_ gotos: ParseGotoTable) {
        count(gotos.columnCount)
        count(gotos.rowCount)
        count(gotos.rowOfState.count)
        rawU32s(gotos.rowOfState)
        rawU32s(gotos.cells)
        ints(gotos.indirectTargets)
    }
}

extension TableFileWriter {
    fileprivate mutating func write(_ table: LexTable) {
        count(table.states.count)
        for state in table.states {
            count(state.transitions.count)
            for (range, target) in state.transitions {
                u32(range.lowerBound)
                u32(range.upperBound)
                int(target)
            }
            optionalInt(state.accepting)
        }
        write(table.keywords)
        count(table.commentPatterns.count)
        for pattern in table.commentPatterns {
            switch pattern {
                case .line(let prefix):
                    u8(0)
                    string(prefix)
                case .block(let open, let close):
                    u8(1)
                    string(open)
                    string(close)
            }
        }
        count(table.tokens.count)
        for token in table.tokens {
            string(token.name)
            bool(token.isNamed)
            bool(token.isExtra)
        }
        write(table.automaton)
        ints(table.modeStarts)
        ints(table.stateModes)
        optionalInt(table.errorMode)
        optionalInt(table.wordToken)
        write(table.keywordTokens)
        count(table.modeValidTokens.count)
        table.modeValidTokens.forEach { ints($0) }
        count(table.modeEmptyTokens.count)
        table.modeEmptyTokens.forEach { optionalInt($0) }
        count(table.modeEmptyAfterSeparator.count)
        table.modeEmptyAfterSeparator.forEach { optionalInt($0) }
        bool(table.modeSource != nil)
        if let source = table.modeSource {
            write(source)
        }
    }

    /// A map of names to integers, in the order of its names.
    private mutating func write(_ map: [String: Int]) {
        count(map.count)
        for (name, value) in map.sorted(by: { $0.key < $1.key }) {
            string(name)
            int(value)
        }
    }

    private mutating func write(_ automaton: LexAutomaton) {
        count(automaton.accepts.count)
        automaton.accepts.forEach { optionalInt($0) }
        rawU32s(automaton.groupStarts)
        count(automaton.groups.count)
        for group in automaton.groups {
            u32(group.set)
            bool(group.skips)
            int(group.target)
        }
        count(automaton.setCount)
        rawU32s(automaton.setStarts)
        rawU32s(automaton.bounds)
    }

    private mutating func write(_ source: LexModeSource) {
        count(source.nfa.states.count)
        for state in source.nfa.states {
            switch state {
                case .advance(let characters, let next, let precedence, let isSeparator):
                    u8(0)
                    count(characters.ranges.count)
                    for range in characters.ranges {
                        u32(range.lowerBound)
                        u32(range.upperBound)
                    }
                    int(next)
                    int(precedence)
                    bool(isSeparator)
                case .split(let targets):
                    u8(1)
                    ints(targets)
                case .accept(let token, let precedence):
                    u8(2)
                    int(token)
                    int(precedence)
            }
        }
        ints(source.nfa.owners)
        ints(source.nfa.starts)
        ints(source.nfa.nullableTokens.sorted())
        count(source.priorities.count)
        for priority in source.priorities {
            int(priority.completionPrecedence)
            int(priority.implicitPrecedence)
            bool(priority.isImmediate)
        }
    }

    fileprivate mutating func write(_ production: ProductionRule) {
        string(production.name)
        int(production.symbolCount)
        strings(production.symbols)
        count(production.fields.count)
        for field in production.fields {
            int(field.step)
            string(field.name)
        }
        count(production.aliases.count)
        for (step, alias) in production.aliases.sorted(by: { $0.key < $1.key }) {
            int(step)
            string(alias.type)
            bool(alias.isNamed)
        }
        int(production.dynamicPrecedence)
    }
}
