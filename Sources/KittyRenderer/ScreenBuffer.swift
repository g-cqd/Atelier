import KittyCodecs

/// A flat grid of cells representing the terminal screen.
public struct ScreenBuffer: Sendable {
    public private(set) var cells: [Cell]
    public let columns: Int
    public let rows: Int
    public var dirty: DirtyTracker

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.cells = [Cell](repeating: .empty, count: columns * rows)
        self.dirty = DirtyTracker(capacity: columns * rows)
    }

    public subscript(row: Int, col: Int) -> Cell {
        get {
            guard row >= 0, row < rows, col >= 0, col < columns else { return .empty }
            return cells[row * columns + col]
        }
        set {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            let idx = row * columns + col
            if cells[idx] != newValue {
                cells[idx] = newValue
                dirty.mark(idx)
            }
        }
    }

    /// Write a string with style starting at (row, col).
    public mutating func write(_ string: String, row: Int, col: Int, style: Style) {
        guard row >= 0, row < rows else { return }
        var c = col
        for char in string {
            guard c >= 0, c < columns else { break }
            self[row, c] = Cell(character: char, style: style, width: 1)
            c += 1
        }
    }

    /// Fill the entire buffer with empty cells.
    public mutating func clear() {
        for i in cells.indices {
            if cells[i] != .empty {
                cells[i] = .empty
                dirty.mark(i)
            }
        }
    }

    /// Fill a rectangular region.
    public mutating func fill(row: Int, col: Int, width: Int, height: Int, cell: Cell) {
        guard row >= 0, row < rows, col >= 0, col < columns, width > 0, height > 0 else { return }
        for r in row..<min(row + height, rows) {
            for c in col..<min(col + width, columns) {
                self[r, c] = cell
            }
        }
    }

    /// Resize the buffer, preserving content where possible.
    public mutating func resize(columns newCols: Int, rows newRows: Int) {
        var newCells = [Cell](repeating: .empty, count: newCols * newRows)
        let copyRows = min(rows, newRows)
        let copyCols = min(columns, newCols)
        for r in 0..<copyRows {
            for c in 0..<copyCols {
                newCells[r * newCols + c] = cells[r * columns + c]
            }
        }
        // Can't reassign self directly for columns/rows since they are let
        self = ScreenBuffer._fromParts(cells: newCells, columns: newCols, rows: newRows)
    }

    private static func _fromParts(cells: [Cell], columns: Int, rows: Int) -> ScreenBuffer {
        var buf = ScreenBuffer(columns: columns, rows: rows)
        buf.cells = cells
        // Mark everything dirty after resize
        for i in 0..<(columns * rows) {
            buf.dirty.mark(i)
        }
        return buf
    }
}
