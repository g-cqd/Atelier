/// Which externals each parse state lets the external scanner read, in the table's `externalNames` order: a
/// collection of one row per state that keeps each distinct row once, since a table's thousands of states share a few
/// dozen of them at most.
public struct ExternalValidity: Sendable, RandomAccessCollection {
    /// The distinct rows.
    private(set) var distinctRows: [[Bool]]
    /// The row of each state, by state.
    private(set) var rowOfState: [UInt32]

    /// The validity of `rows`, one per state.
    public init(rows: [[Bool]] = []) {
        var distinctRows: [[Bool]] = []
        var index: [[Bool]: UInt32] = [:]
        rowOfState = rows.map { row in
            if let existing = index[row] { return existing }
            let position = UInt32(distinctRows.count)
            index[row] = position
            distinctRows.append(row)
            return position
        }
        self.distinctRows = distinctRows
    }

    /// The validity made of its parts, as a cache file's reader checked them.
    init(distinctRows: [[Bool]], rowOfState: [UInt32]) {
        self.distinctRows = distinctRows
        self.rowOfState = rowOfState
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { rowOfState.count }

    /// The externals valid in `state`.
    public subscript(state: Int) -> [Bool] {
        distinctRows[Int(rowOfState[state])]
    }
}

extension ExternalValidity: Equatable {
    /// Whether both have the same row for every state, however they store them.
    public static func == (lhs: ExternalValidity, rhs: ExternalValidity) -> Bool {
        lhs.elementsEqual(rhs)
    }
}

extension ExternalValidity: Codable {
    /// The validity encodes as its rows, one per state, as the tables' JSON always has.
    public init(from decoder: any Decoder) throws {
        self.init(rows: try decoder.singleValueContainer().decode([[Bool]].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Array(self))
    }
}

extension ExternalValidity {
    /// Whether each state's row exists. Validity built from rows always is; one read back from a file may not be.
    var isWellFormed: Bool {
        rowOfState.allSatisfy { Int($0) < distinctRows.count }
    }

    /// Whether every state's row has `count` externals.
    /// - Complexity: O(r) in the distinct rows, a few dozen at most, not in the states.
    public func rowsAll(haveCount count: Int) -> Bool {
        distinctRows.allSatisfy { $0.count == count }
    }
}
