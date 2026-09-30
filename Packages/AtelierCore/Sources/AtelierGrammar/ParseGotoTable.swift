/// A parse table's GOTO targets by state and non-terminal, kept small as ``ParseActionTable`` keeps actions: a 32-bit
/// cell per non-terminal of each distinct row, each state pointing at its row.
///
/// A cell is 0 for no target, the target plus one below 2³¹, or, with its top bit set, an index into
/// ``indirectTargets`` for a target no cell can hold, as a table built by hand may have.
public struct ParseGotoTable: Sendable {
    /// The non-terminals each row has a cell for.
    public private(set) var columnCount: Int
    /// The number of distinct rows.
    private(set) var rowCount: Int
    /// The row of each state, by state.
    @usableFromInline private(set) var rowOfState: [UInt32]
    /// The rows' cells, row after row, ``columnCount`` each.
    @usableFromInline private(set) var cells: [UInt32]
    /// The targets cells refer to, for those too large or negative to hold.
    @usableFromInline private(set) var indirectTargets: [Int]

    @usableFromInline static let indirectFlag: UInt32 = 1 << 31

    /// The table of `rows`, one per state. A row shorter than the longest has no target past its end.
    public init(rows: [[Int?]]) {
        var builder = Builder(columnCount: rows.map(\.count).max() ?? 0)
        for row in rows {
            builder.append(row)
        }
        self = builder.table
    }

    /// Builds a table one state's row at a time, storing each distinct row once.
    struct Builder {
        private(set) var table: ParseGotoTable
        private var rowIndex: [[UInt32]: UInt32] = [:]

        init(columnCount: Int) {
            table = ParseGotoTable(
                columnCount: columnCount, rowCount: 0, rowOfState: [], cells: [], indirectTargets: [])
        }

        /// Adds the next state, whose targets are `row`: no target past its end.
        mutating func append(_ row: [Int?]) {
            precondition(
                row.count <= table.columnCount, "a row of \(row.count) targets in a table of \(table.columnCount)")
            var encoded = [UInt32](repeating: 0, count: table.columnCount)
            for (column, target) in row.enumerated() {
                encoded[column] = table.cell(for: target)
            }
            if let existing = rowIndex[encoded] {
                table.rowOfState.append(existing)
                return
            }
            rowIndex[encoded] = UInt32(table.rowCount)
            table.rowOfState.append(UInt32(table.rowCount))
            table.rowCount += 1
            table.cells.append(contentsOf: encoded)
        }
    }

    /// The table made of its parts, as a cache file's reader checked them.
    init(columnCount: Int, rowCount: Int, rowOfState: [UInt32], cells: [UInt32], indirectTargets: [Int]) {
        self.columnCount = columnCount
        self.rowCount = rowCount
        self.rowOfState = rowOfState
        self.cells = cells
        self.indirectTargets = indirectTargets
    }

    /// The number of states.
    public var stateCount: Int { rowOfState.count }

    /// The state `state` goes to after reducing to `nonTerminal`; nil for none.
    ///
    /// Setting a cell copies the state's row first, so it costs O(``columnCount``): for building tables by hand.
    @inlinable
    public subscript(state: Int, nonTerminal: Int) -> Int? {
        @inline(__always) get {
            precondition(0 <= nonTerminal && nonTerminal < columnCount, "non-terminal \(nonTerminal) outside the table")
            return target(ofCell: cells[Int(rowOfState[state]) &* columnCount &+ nonTerminal])
        }
        set { setTarget(newValue, state: state, nonTerminal: nonTerminal) }
    }

    /// Gives `state` its own copy of its row, with `target` for `nonTerminal`.
    @usableFromInline
    mutating func setTarget(_ target: Int?, state: Int, nonTerminal: Int) {
        precondition(0 <= nonTerminal && nonTerminal < columnCount, "non-terminal \(nonTerminal) outside the table")
        let start = Int(rowOfState[state]) * columnCount
        var row = Array(cells[start ..< start + columnCount])
        row[nonTerminal] = cell(for: target)
        rowOfState[state] = UInt32(rowCount)
        rowCount += 1
        cells.append(contentsOf: row)
    }

    /// The targets of `state`, by non-terminal.
    /// - Complexity: O(``columnCount``).
    public func row(_ state: Int) -> [Int?] {
        let start = Int(rowOfState[state]) * columnCount
        return cells[start ..< start + columnCount].map(target(ofCell:))
    }

    /// Every state's targets, by state then non-terminal.
    /// - Complexity: O(states × non-terminals): for tests and diagnostics, not for reading a table.
    public var rows: [[Int?]] {
        rowOfState.indices.map(row)
    }

    @inlinable @inline(__always)
    func target(ofCell cell: UInt32) -> Int? {
        if cell == 0 { return nil }
        return cell & Self.indirectFlag == 0 ? Int(cell) - 1 : indirectTargets[Int(cell & ~Self.indirectFlag)]
    }

    fileprivate mutating func cell(for target: Int?) -> UInt32 {
        guard let target else { return 0 }
        if 0 <= target && target < Int(Self.indirectFlag) - 1 {
            return UInt32(target + 1)
        }
        precondition(indirectTargets.count < Int(Self.indirectFlag), "too many indirect targets")
        indirectTargets.append(target)
        return Self.indirectFlag | UInt32(indirectTargets.count - 1)
    }
}

extension ParseGotoTable: Equatable {
    /// Whether both tables have the same target in every state and for every non-terminal, however they store them.
    public static func == (lhs: ParseGotoTable, rhs: ParseGotoTable) -> Bool {
        guard lhs.columnCount == rhs.columnCount, lhs.stateCount == rhs.stateCount else { return false }
        if lhs.rowOfState == rhs.rowOfState, lhs.cells == rhs.cells, lhs.indirectTargets == rhs.indirectTargets {
            return true
        }
        return lhs.rowOfState.indices.allSatisfy { lhs.row($0) == rhs.row($0) }
    }
}

extension ParseGotoTable: Codable {
    /// A table encodes as its rows of targets, one per state, as the tables' JSON always has.
    public init(from decoder: any Decoder) throws {
        self.init(rows: try decoder.singleValueContainer().decode([[Int?]].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }
}

extension ParseGotoTable {
    /// Whether every read of the table lands inside it: each state's row and each indirect cell's target exist. A
    /// table built from rows always is; one read back from a file may not be.
    /// - Complexity: O(n) in the stored cells.
    var isWellFormed: Bool {
        let (size, overflow) = rowCount.multipliedReportingOverflow(by: columnCount)
        guard columnCount >= 0, rowCount >= 0, !overflow, cells.count == size else { return false }
        return rowOfState.allSatisfy { Int($0) < rowCount }
            && cells.allSatisfy { $0 & Self.indirectFlag == 0 || Int($0 & ~Self.indirectFlag) < indirectTargets.count }
    }

    /// Whether every target a cell holds is one of `states`.
    /// - Complexity: O(n) in the stored cells.
    func targetsAll(in states: Range<Int>) -> Bool {
        cells.allSatisfy { cell in target(ofCell: cell).map(states.contains) ?? true }
    }
}
