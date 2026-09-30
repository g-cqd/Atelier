/// A parse table's actions by state and terminal, kept small: a 32-bit cell per terminal of each distinct row, each
/// state pointing at its row, and the actions a cell cannot hold itself, reductions and conflicts, in a list of
/// their own that cells index.
///
/// Most of a table's cells are errors and many states share a row, so this keeps a tenth or less of what a row of
/// ``Action`` values per state takes, and reads a cell with two array reads.
public struct ParseActionTable: Sendable {
    /// The terminals each row has a cell for.
    public private(set) var columnCount: Int
    /// The number of distinct rows.
    private(set) var rowCount: Int
    /// The row of each state, by state.
    @usableFromInline private(set) var rowOfState: [UInt32]
    /// The rows' cells, row after row, ``columnCount`` each.
    @usableFromInline private(set) var cells: [UInt32]
    /// The actions cells refer to, each once.
    public private(set) var indirectActions: [Action]

    /// A cell's kind is in its top two bits, and its payload, a shift's state or an index into ``indirectActions``,
    /// below them.
    @usableFromInline static let payloadBits: UInt32 = 30
    @usableFromInline static let payloadMask: UInt32 = (1 << payloadBits) - 1
    @usableFromInline static let errorCell: UInt32 = 0
    @usableFromInline static let shiftTag: UInt32 = 1
    @usableFromInline static let acceptCell: UInt32 = 2 << payloadBits
    @usableFromInline static let indirectTag: UInt32 = 3

    /// The table of `rows`, one per state. A row shorter than the longest reads as errors past its end.
    public init(rows: [[Action]]) {
        var builder = Builder(columnCount: rows.map(\.count).max() ?? 0)
        for row in rows {
            builder.append(row + repeatElement(Action.error, count: builder.columnCount - row.count))
        }
        self = builder.table
    }

    /// The table made of its parts, as a cache file's reader checked them.
    init(columnCount: Int, rowCount: Int, rowOfState: [UInt32], cells: [UInt32], indirectActions: [Action]) {
        self.columnCount = columnCount
        self.rowCount = rowCount
        self.rowOfState = rowOfState
        self.cells = cells
        self.indirectActions = indirectActions
    }

    /// The number of states.
    public var stateCount: Int { rowOfState.count }

    /// The action of `state` on `terminal`.
    ///
    /// Reading one is the parser's innermost step, inlined into it. Setting a cell copies the state's row first, so it
    /// costs O(``columnCount``): for building tables by hand.
    @inlinable
    public subscript(state: Int, terminal: Int) -> Action {
        @inline(__always) get { action(ofCell: cell(state: state, terminal: terminal)) }
        set { setAction(newValue, state: state, terminal: terminal) }
    }

    /// Gives `state` its own copy of its row, with `action` on `terminal`.
    @usableFromInline
    mutating func setAction(_ action: Action, state: Int, terminal: Int) {
        precondition(0 <= terminal && terminal < columnCount, "terminal \(terminal) outside the table")
        var row = Array(rowCells(Int(rowOfState[state])))
        if let cell = Self.inlineCell(for: action) {
            row[terminal] = cell
        } else {
            row[terminal] = Self.indirectCell(indirectActions.count)
            indirectActions.append(action)
        }
        rowOfState[state] = UInt32(rowCount)
        rowCount += 1
        cells.append(contentsOf: row)
    }

    /// Whether `state` has no action on `terminal`.
    @inlinable @inline(__always)
    public func isError(state: Int, terminal: Int) -> Bool {
        cell(state: state, terminal: terminal) == Self.errorCell
    }

    /// The actions of `state`, by terminal.
    /// - Complexity: O(``columnCount``).
    public func row(_ state: Int) -> [Action] {
        rowCells(Int(rowOfState[state])).map(action(ofCell:))
    }

    /// Every state's actions, by state then terminal.
    /// - Complexity: O(states × terminals): for tests and diagnostics, not for reading a table.
    public var rows: [[Action]] {
        rowOfState.indices.map(row)
    }

    @inlinable @inline(__always)
    func cell(state: Int, terminal: Int) -> UInt32 {
        precondition(0 <= terminal && terminal < columnCount, "terminal \(terminal) outside the table")
        return cells[Int(rowOfState[state]) &* columnCount &+ terminal]
    }

    private func rowCells(_ row: Int) -> ArraySlice<UInt32> {
        cells[row * columnCount ..< (row + 1) * columnCount]
    }

    @inlinable @inline(__always)
    func action(ofCell cell: UInt32) -> Action {
        switch cell >> Self.payloadBits {
            case Self.shiftTag: .shift(Int(cell & Self.payloadMask))
            case Self.indirectTag: indirectActions[Int(cell & Self.payloadMask)]
            default: cell == Self.acceptCell ? .accept : .error
        }
    }

    /// The cell of `action` when a cell can hold it; nil for one that goes in ``indirectActions``.
    static func inlineCell(for action: Action) -> UInt32? {
        switch action {
            case .error: errorCell
            case .accept: acceptCell
            case .shift(let state) where 0 <= state && state <= Int(payloadMask):
                shiftTag << payloadBits | UInt32(state)
            case .shift, .reduce, .conflict: nil
        }
    }

    /// The cell that refers to ``indirectActions``'s action at `position`.
    static func indirectCell(_ position: Int) -> UInt32 {
        precondition(position <= Int(payloadMask), "too many distinct reductions and conflicts")
        return indirectTag << payloadBits | UInt32(position)
    }

    /// Builds a table one state's row at a time, storing each distinct row and indirect action once.
    struct Builder {
        private(set) var table: ParseActionTable
        private var rowIndex: [[UInt32]: UInt32] = [:]
        private var actionIndex: [Action: Int] = [:]

        init(columnCount: Int) {
            table = ParseActionTable(
                columnCount: columnCount, rowCount: 0, rowOfState: [], cells: [], indirectActions: [])
        }

        var columnCount: Int { table.columnCount }

        /// Adds the next state, whose actions are `row`, ``columnCount`` of them.
        mutating func append(_ row: [Action]) {
            precondition(row.count == columnCount, "a row of \(row.count) actions in a table of \(columnCount)")
            var encoded: [UInt32] = []
            encoded.reserveCapacity(row.count)
            for action in row {
                if let cell = ParseActionTable.inlineCell(for: action) {
                    encoded.append(cell)
                } else if let position = actionIndex[action] {
                    encoded.append(ParseActionTable.indirectCell(position))
                } else {
                    let position = table.indirectActions.count
                    encoded.append(ParseActionTable.indirectCell(position))
                    actionIndex[action] = position
                    table.indirectActions.append(action)
                }
            }
            if let existing = rowIndex[encoded] {
                table.rowOfState.append(existing)
                return
            }
            let position = UInt32(table.rowCount)
            rowIndex[encoded] = position
            table.rowOfState.append(position)
            table.rowCount += 1
            table.cells.append(contentsOf: encoded)
        }
    }
}

extension ParseActionTable: Equatable {
    /// Whether both tables have the same action in every state and on every terminal, however they store them.
    public static func == (lhs: ParseActionTable, rhs: ParseActionTable) -> Bool {
        guard lhs.columnCount == rhs.columnCount, lhs.stateCount == rhs.stateCount else { return false }
        if lhs.rowOfState == rhs.rowOfState, lhs.cells == rhs.cells, lhs.indirectActions == rhs.indirectActions {
            return true
        }
        return lhs.rowOfState.indices.allSatisfy { lhs.row($0) == rhs.row($0) }
    }
}

extension ParseActionTable: Codable {
    /// A table encodes as its rows of actions, one per state, as the tables' JSON always has.
    public init(from decoder: any Decoder) throws {
        self.init(rows: try decoder.singleValueContainer().decode([[Action]].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }
}

extension ParseActionTable {
    /// Whether every read of the table lands inside it: each state's row and each indirect cell's action exist, and
    /// each cell is one the table writes. A table built from rows always is; one read back from a file may not be.
    /// - Complexity: O(n) in the stored cells.
    var isWellFormed: Bool {
        let (size, overflow) = rowCount.multipliedReportingOverflow(by: columnCount)
        guard columnCount >= 0, rowCount >= 0, !overflow, cells.count == size else { return false }
        return rowOfState.allSatisfy { Int($0) < rowCount }
            && cells.allSatisfy { cell in
                switch cell >> Self.payloadBits {
                    case Self.shiftTag: true
                    case Self.indirectTag: Int(cell & Self.payloadMask) < indirectActions.count
                    default: cell == Self.errorCell || cell == Self.acceptCell
                }
            }
    }

    /// Whether every shift a cell holds goes to one of `states`.
    /// - Complexity: O(n) in the stored cells.
    func shiftsAll(into states: Range<Int>) -> Bool {
        cells.allSatisfy { cell in
            cell >> Self.payloadBits != Self.shiftTag || states.contains(Int(cell & Self.payloadMask))
        }
    }
}
