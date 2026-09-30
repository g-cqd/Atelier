/// Reads a table file's payload front to back (``TableFile``), checking each count and length against the bytes left
/// before it reads or allocates anything, and each index against what it indexes.
///
/// It holds a pointer into bytes it does not own. Owner: the caller's buffer, a `Data` in
/// ``ParseTableCompiler/CompilationResult/init(tableFile:)``. Lifetime: a reader is made and dropped inside the
/// `withUnsafeBytes` call that lends the buffer, and no pointer it reads through leaves its methods. Bounds: every
/// read goes through ``require(_:)``, which checks it against `bytes.count`.
struct TableFileReader {
    private let bytes: UnsafeRawBufferPointer
    private var offset = 0
    /// The file's strings, read first.
    private var stringTable: [String] = []

    init(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { offset == bytes.count }

    private var remaining: Int { bytes.count - offset }

    /// Checks that `byteCount` more bytes are there to read.
    private func require(_ byteCount: Int) throws(TableFileError) {
        guard byteCount >= 0, byteCount <= remaining else { throw .truncated }
    }

    // MARK: - Values

    mutating func u8() throws(TableFileError) -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u32() throws(TableFileError) -> UInt32 {
        try require(4)
        defer { offset += 4 }
        return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    mutating func u64() throws(TableFileError) -> UInt64 {
        try require(8)
        defer { offset += 8 }
        return UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    mutating func int() throws(TableFileError) -> Int {
        Int(Int64(bitPattern: try u64()))
    }

    mutating func bool() throws(TableFileError) -> Bool {
        switch try u8() {
            case 0: return false
            case 1: return true
            default: throw .malformed("a flag other than 0 or 1")
        }
    }

    mutating func optionalInt() throws(TableFileError) -> Int? {
        let isPresent = try bool()
        let value = try int()
        return isPresent ? value : nil
    }

    /// A count of things each at least `minimumSize` bytes long, which must fit in the bytes left.
    mutating func count(minimumSize: Int) throws(TableFileError) -> Int {
        let count = Int(try u32())
        guard count <= remaining / max(minimumSize, 1) else { throw .truncated }
        return count
    }

    mutating func string() throws(TableFileError) -> String {
        let index = Int(try u32())
        guard index < stringTable.count else { throw .malformed("a string index past the strings") }
        return stringTable[index]
    }

    mutating func strings() throws(TableFileError) -> [String] {
        try array(minimumSize: 4) { (reader: inout Self) throws(TableFileError) in try reader.string() }
    }

    mutating func ints() throws(TableFileError) -> [Int] {
        try array(minimumSize: 8) { (reader: inout Self) throws(TableFileError) in try reader.int() }
    }

    mutating func bools() throws(TableFileError) -> [Bool] {
        try array(minimumSize: 1) { (reader: inout Self) throws(TableFileError) in try reader.bool() }
    }

    /// A count, then that many elements read by `element`, each at least `minimumSize` bytes long.
    mutating func array<Element>(
        minimumSize: Int, _ element: (inout TableFileReader) throws(TableFileError) -> Element
    ) throws(TableFileError) -> [Element] {
        let elementCount = try count(minimumSize: minimumSize)
        var elements: [Element] = []
        elements.reserveCapacity(elementCount)
        for _ in 0 ..< elementCount {
            elements.append(try element(&self))
        }
        return elements
    }

    /// `count` 32-bit integers, copied in one go.
    mutating func rawU32s(count: Int) throws(TableFileError) -> [UInt32] {
        guard count >= 0, count <= remaining / 4 else { throw .truncated }
        let byteCount = count * 4
        let source = UnsafeRawBufferPointer(rebasing: bytes[offset ..< offset + byteCount])
        // Bounds: `source` is the `byteCount` bytes checked above, and the array's storage holds exactly `count`
        // 32-bit integers, `byteCount` bytes, which the copy fills before `initializedCount` claims them.
        let values = [UInt32](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            UnsafeMutableRawBufferPointer(buffer).copyMemory(from: source)
            initializedCount = count
        }
        offset += byteCount
        #if _endian(little)
            return values
        #else
            return values.map { UInt32(littleEndian: $0) }
        #endif
    }

    /// Reads the file's strings, which every later string refers to by index.
    mutating func readStrings() throws(TableFileError) {
        let read = try array(minimumSize: 4) { (reader: inout Self) throws(TableFileError) -> String in
            let length = Int(try reader.u32())
            try reader.require(length)
            let text = UnsafeRawBufferPointer(rebasing: reader.bytes[reader.offset ..< reader.offset + length])
            reader.offset += length
            guard let string = String(validating: text, as: UTF8.self) else {
                throw .malformed("a string that is not UTF-8")
            }
            return string
        }
        stringTable = read
    }
}

// MARK: - Tables

extension TableFileReader {
    mutating func readCompilationResult() throws(TableFileError) -> ParseTableCompiler.CompilationResult {
        try readStrings()
        let parseTable = try readParseTable()
        let lexTable = try readLexTable()
        let productions = try array(minimumSize: 32) { (reader: inout Self) throws(TableFileError) in
            try reader.readProduction()
        }
        return ParseTableCompiler.CompilationResult(
            parseTable: parseTable, lexTable: lexTable, productions: productions)
    }

    private mutating func readParseTable() throws(TableFileError) -> ParseTable {
        let stateCount = try int()
        guard stateCount >= 0 else { throw .malformed("a negative number of states") }
        let symbols = try strings()
        let terminals = try strings()
        let nonTerminals = try strings()
        let actions = try readActions()
        let gotos = try readGotos()
        let externalNames = try strings()
        let externalSymbols = try strings()
        let distinctRows = try array(minimumSize: 4) { (reader: inout Self) throws(TableFileError) in try reader.bools()
        }
        let rowOfState = try rawU32s(count: try count(minimumSize: 4))
        let validExternals = ExternalValidity(distinctRows: distinctRows, rowOfState: rowOfState)
        guard validExternals.isWellFormed else { throw .malformed("a state's external validity past the rows") }
        let externalIsExtra = try bools()
        var lostShifts: [Int: [Int: Int]] = [:]
        let lostShiftStates = try count(minimumSize: 12)
        for _ in 0 ..< lostShiftStates {
            let state = try int()
            var shifts: [Int: Int] = [:]
            let shiftCount = try count(minimumSize: 16)
            for _ in 0 ..< shiftCount {
                let terminal = try int()
                guard shifts.updateValue(try int(), forKey: terminal) == nil else {
                    throw .malformed("a lost shift listed twice")
                }
            }
            guard lostShifts.updateValue(shifts, forKey: state) == nil else {
                throw .malformed("a state's lost shifts listed twice")
            }
        }
        return ParseTable(
            stateCount: stateCount, symbols: symbols, terminals: terminals, nonTerminals: nonTerminals,
            actions: actions, gotos: gotos, externalNames: externalNames, externalSymbols: externalSymbols,
            validExternals: validExternals, externalIsExtra: externalIsExtra, lostShifts: lostShifts)
    }

    private mutating func readActions() throws(TableFileError) -> ParseActionTable {
        let columnCount = Int(try u32())
        let rowCount = Int(try u32())
        let rowOfState = try rawU32s(count: try count(minimumSize: 4))
        let (cellCount, overflow) = rowCount.multipliedReportingOverflow(by: columnCount)
        guard !overflow else { throw .truncated }
        let cells = try rawU32s(count: cellCount)
        let indirectActions = try array(minimumSize: 1) { (reader: inout Self) throws(TableFileError) in
            try reader.action(nested: false)
        }
        let table = ParseActionTable(
            columnCount: columnCount, rowCount: rowCount, rowOfState: rowOfState, cells: cells,
            indirectActions: indirectActions)
        guard table.isWellFormed else { throw .malformed("an action cell or state row past the table") }
        return table
    }

    /// An action; a conflict holds no conflict, which the compiler never builds and which would let a file nest
    /// without bound.
    private mutating func action(nested: Bool) throws(TableFileError) -> Action {
        switch try u8() {
            case 0:
                return .shift(try int())
            case 1:
                let rule = try int()
                let count = try int()
                return .reduce(ruleIndex: rule, count: count, nonTerminal: try string())
            case 2:
                return .accept
            case 3:
                return .error
            case 4 where !nested:
                return .conflict(
                    try array(minimumSize: 1) { (reader: inout Self) throws(TableFileError) in
                        try reader.action(nested: true)
                    })
            default:
                throw .malformed("an unknown action, or a conflict within a conflict")
        }
    }

    private mutating func readGotos() throws(TableFileError) -> ParseGotoTable {
        let columnCount = Int(try u32())
        let rowCount = Int(try u32())
        let rowOfState = try rawU32s(count: try count(minimumSize: 4))
        let (cellCount, overflow) = rowCount.multipliedReportingOverflow(by: columnCount)
        guard !overflow else { throw .truncated }
        let cells = try rawU32s(count: cellCount)
        let table = ParseGotoTable(
            columnCount: columnCount, rowCount: rowCount, rowOfState: rowOfState, cells: cells,
            indirectTargets: try ints())
        guard table.isWellFormed else { throw .malformed("a GOTO cell or state row past the table") }
        return table
    }

    private mutating func readProduction() throws(TableFileError) -> ProductionRule {
        let name = try string()
        let symbolCount = try int()
        let symbols = try strings()
        let fields = try array(minimumSize: 12) { (reader: inout Self) throws(TableFileError) in
            ProductionField(step: try reader.int(), name: try reader.string())
        }
        var aliases: [Int: SymbolAlias] = [:]
        let aliasCount = try count(minimumSize: 13)
        for _ in 0 ..< aliasCount {
            let step = try int()
            let alias = SymbolAlias(type: try string(), isNamed: try bool())
            guard aliases.updateValue(alias, forKey: step) == nil else { throw .malformed("an alias listed twice") }
        }
        return ProductionRule(
            name: name, symbolCount: symbolCount, symbols: symbols, fields: fields, aliases: aliases,
            dynamicPrecedence: try int())
    }
}

extension TableFileReader {
    fileprivate mutating func readLexTable() throws(TableFileError) -> LexTable {
        let states = try array(minimumSize: 13) { (reader: inout Self) throws(TableFileError) -> LexState in
            let transitions = try reader.array(minimumSize: 16) {
                (reader: inout Self) throws(TableFileError) -> (ClosedRange<UInt32>, Int) in
                let lower = try reader.u32()
                let upper = try reader.u32()
                // A range is built only from ordered bounds, which would otherwise trap.
                guard lower <= upper else { throw .malformed("a keyword-trie move on an inverted range") }
                return (lower ... upper, try reader.int())
            }
            return LexState(transitions: transitions, accepting: try reader.optionalInt())
        }
        let keywords = try readMap()
        let commentPatterns = try array(minimumSize: 5) {
            (reader: inout Self) throws(TableFileError) -> CommentPattern in
            switch try reader.u8() {
                case 0: return .line(prefix: try reader.string())
                case 1: return .block(open: try reader.string(), close: try reader.string())
                default: throw .malformed("an unknown comment pattern")
            }
        }
        let tokens = try array(minimumSize: 6) { (reader: inout Self) throws(TableFileError) in
            LexToken(name: try reader.string(), isNamed: try reader.bool(), isExtra: try reader.bool())
        }
        let automaton = try readAutomaton()
        let modeStarts = try ints()
        let stateModes = try ints()
        let errorMode = try optionalInt()
        let wordToken = try optionalInt()
        let keywordTokens = try readMap()
        let modeValidTokens = try array(minimumSize: 4) { (reader: inout Self) throws(TableFileError) in
            try reader.ints()
        }
        let modeEmptyTokens = try array(minimumSize: 9) { (reader: inout Self) throws(TableFileError) in
            try reader.optionalInt()
        }
        let modeEmptyAfterSeparator = try array(minimumSize: 9) { (reader: inout Self) throws(TableFileError) in
            try reader.optionalInt()
        }
        let modeSource: LexModeSource? = try bool() ? readModeSource() : nil
        return LexTable(
            states: states, keywords: keywords, commentPatterns: commentPatterns, tokens: tokens,
            automaton: automaton, modeStarts: modeStarts, stateModes: stateModes, errorMode: errorMode,
            wordToken: wordToken, keywordTokens: keywordTokens, modeValidTokens: modeValidTokens,
            modeEmptyTokens: modeEmptyTokens, modeEmptyAfterSeparator: modeEmptyAfterSeparator,
            modeSource: modeSource)
    }

    /// A map of names to integers; a name listed twice is malformed.
    private mutating func readMap() throws(TableFileError) -> [String: Int] {
        let entryCount = try count(minimumSize: 12)
        var map: [String: Int] = [:]
        map.reserveCapacity(entryCount)
        for _ in 0 ..< entryCount {
            let name = try string()
            guard map.updateValue(try int(), forKey: name) == nil else { throw .malformed("a name listed twice") }
        }
        return map
    }

    private mutating func readAutomaton() throws(TableFileError) -> LexAutomaton {
        let accepts = try array(minimumSize: 9) { (reader: inout Self) throws(TableFileError) in
            try reader.optionalInt()
        }
        let groupStarts = try rawU32s(count: accepts.count + 1)
        let groups = try array(minimumSize: 13) { (reader: inout Self) throws(TableFileError) in
            LexAutomaton.Group(set: try reader.u32(), skips: try reader.bool(), target: try reader.int())
        }
        let setStarts = try rawU32s(count: try count(minimumSize: 4) + 1)
        let (boundCount, overflow) = Int(setStarts.last ?? 0).multipliedReportingOverflow(by: 2)
        guard !overflow else { throw .truncated }
        let automaton = LexAutomaton(
            accepts: accepts, groupStarts: groupStarts, groups: groups, setStarts: setStarts,
            bounds: try rawU32s(count: boundCount))
        guard automaton.isWellFormed else { throw .malformed("a lexer group or set past the automaton") }
        return automaton
    }

    private mutating func readModeSource() throws(TableFileError) -> LexModeSource {
        let states = try array(minimumSize: 5) { (reader: inout Self) throws(TableFileError) -> TokenNFA.State in
            switch try reader.u8() {
                case 0:
                    let ranges = try reader.array(minimumSize: 8) {
                        (reader: inout Self) throws(TableFileError) -> (lower: UInt32, upper: UInt32) in
                        (try reader.u32(), try reader.u32())
                    }
                    guard let characters = ScalarRanges(validating: ranges) else {
                        throw .malformed("a token automaton's ranges out of order")
                    }
                    return .advance(
                        characters, next: try reader.int(), precedence: try reader.int(),
                        isSeparator: try reader.bool())
                case 1:
                    return .split(try reader.ints())
                case 2:
                    return .accept(token: try reader.int(), precedence: try reader.int())
                default:
                    throw .malformed("an unknown token automaton state")
            }
        }
        let owners = try ints()
        let starts = try ints()
        let nullable = try ints()
        let nullableTokens = Set(nullable)
        guard nullableTokens.count == nullable.count else { throw .malformed("a nullable token listed twice") }
        let priorities = try array(minimumSize: 17) { (reader: inout Self) throws(TableFileError) in
            LexTokenPriority(
                completionPrecedence: try reader.int(), implicitPrecedence: try reader.int(),
                isImmediate: try reader.bool())
        }
        return LexModeSource(
            nfa: TokenNFA(states: states, owners: owners, starts: starts, nullableTokens: nullableTokens),
            priorities: priorities)
    }
}
