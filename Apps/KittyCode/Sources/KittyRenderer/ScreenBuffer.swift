import AtelierText
import KittyCodecs
public import KittyStyle

/// A flat grid of cells representing the terminal screen.
public struct ScreenBuffer: Sendable {
    /// The flat array of cells stored in row-major order (row * columns + col).
    public private(set) var cells: ContiguousArray<Cell>

    /// The number of columns (horizontal cells) in the buffer.
    public let columns: Int

    /// The number of rows (vertical cells) in the buffer.
    public let rows: Int

    /// Tracks which cell indices have been modified since the last flush.
    public var dirty: DirtyTracker

    /// Creates a new buffer filled with empty cells.
    ///
    /// - Parameters:
    ///   - columns: The number of horizontal cells.
    ///   - rows: The number of vertical cells.
    public init(columns: Int, rows: Int) {
        let safeColumns = max(0, columns)
        let safeRows = max(0, rows)
        let (capacity, overflow) = safeColumns.multipliedReportingOverflow(by: safeRows)
        precondition(!overflow, "ScreenBuffer size overflows Int: columns=\(columns), rows=\(rows)")
        self.columns = safeColumns
        self.rows = safeRows
        self.cells = ContiguousArray<Cell>(repeating: .empty, count: capacity)
        self.dirty = DirtyTracker(capacity: capacity)
    }

    /// Accesses the cell at the given row and column.
    ///
    /// Out-of-bounds reads return `Cell.empty`; out-of-bounds writes are silently ignored.
    /// The setter only marks the index dirty when the new value differs from the current one.
    public subscript(row: Int, col: Int) -> Cell {
        get {
            guard row >= 0, row < rows, col >= 0, col < columns else { return .empty }
            return cells[row &* columns &+ col]
        }
        set {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            let idx = row &* columns &+ col
            if cells[idx] != newValue {
                cells[idx] = newValue
                dirty.mark(idx)
            }
        }
    }

    /// Writes a string with the given style into the buffer starting at the specified position.
    ///
    /// Wide characters (CJK, fullwidth) occupy two columns. A continuation cell is placed
    /// in the second column. Characters that would extend past the buffer edge are dropped.
    ///
    /// - Parameters:
    ///   - string: The text to write.
    ///   - row: The zero-based row index at which to begin writing.
    ///   - col: The zero-based column index at which to begin writing.
    ///   - style: The visual style to apply to every character in `string`.
    public mutating func write(_ string: String, row: Int, col: Int, style: Style) {
        guard row >= 0, row < rows, col >= 0 else { return }
        var c = col
        for char in string {
            let w = UnicodeWidth.displayWidth(of: char)
            guard w > 0 else { continue }
            if w == 2 {
                guard c + 1 < columns else { break }
                self[row, c] = Cell(character: char, style: style, width: 2)
                self[row, c + 1] = Cell(character: "\0", style: style, width: 0)
                c += 2
            } else {
                guard c < columns else { break }
                self[row, c] = Cell(character: char, style: style, width: 1)
                if c + 1 < columns, self[row, c + 1].width == 0 {
                    self[row, c + 1] = .empty
                }
                c += 1
            }
        }
    }

    /// Replaces every cell in the buffer with `Cell.empty`, marking changed cells dirty.
    public mutating func clear() {
        for i in cells.indices where cells[i] != .empty {
            cells[i] = .empty
            dirty.mark(i)
        }
    }

    /// Fills a rectangular region of the buffer with the given cell value.
    ///
    /// The region is clamped to the buffer bounds. Out-of-bounds or zero-area rectangles are ignored.
    ///
    /// - Parameters:
    ///   - row: The zero-based row index of the top-left corner.
    ///   - col: The zero-based column index of the top-left corner.
    ///   - width: The number of columns to fill.
    ///   - height: The number of rows to fill.
    ///   - cell: The cell value to write into every position in the rectangle.
    public mutating func fill(row: Int, col: Int, width: Int, height: Int, cell: Cell) {
        guard row >= 0, row < rows, col >= 0, col < columns, width > 0, height > 0 else { return }
        for r in row ..< min(row + height, rows) {
            for c in col ..< min(col + width, columns) {
                self[r, c] = cell
            }
        }
    }

    /// Shifts rows within a rectangular region vertically by `delta` rows.
    ///
    /// Positive `delta` shifts content up (for scroll-down); negative shifts down (for scroll-up).
    /// Cells in the vacated rows are left unchanged — the caller's renderer will overwrite them.
    /// No dirty bits are set by the shift itself; the subsequent render marks only cells that
    /// differ from the shifted content.
    ///
    /// - Parameters:
    ///   - regionY: The top row of the region.
    ///   - regionHeight: The number of rows in the region.
    ///   - regionX: The left column of the region.
    ///   - regionWidth: The number of columns in the region.
    ///   - delta: Number of rows to shift (positive = up, negative = down).
    public mutating func shiftRows(
        regionY: Int, regionHeight: Int,
        regionX: Int, regionWidth: Int,
        delta: Int
    ) {
        guard delta != 0, regionWidth > 0, regionHeight > 0, abs(delta) < regionHeight else {
            return
        }

        if delta > 0 {
            // Scroll down: content moves up
            for row in regionY ..< (regionY + regionHeight - delta) {
                let dstBase = row &* columns
                let srcBase = (row &+ delta) &* columns
                for col in regionX ..< (regionX + regionWidth) {
                    cells[dstBase &+ col] = cells[srcBase &+ col]
                }
            }
        } else {
            let absDelta = -delta
            for row in stride(from: regionY + regionHeight - 1, through: regionY + absDelta, by: -1) {
                let dstBase = row &* columns
                let srcBase = (row &- absDelta) &* columns
                for col in regionX ..< (regionX + regionWidth) {
                    cells[dstBase &+ col] = cells[srcBase &+ col]
                }
            }
        }
    }

    /// Resizes the buffer to the new dimensions, preserving the overlapping content.
    ///
    /// Cells within the intersection of the old and new dimensions are copied over.
    /// All cells in the new buffer are marked dirty so the next flush redraws the full viewport.
    ///
    /// - Parameters:
    ///   - newCols: The new number of columns.
    ///   - newRows: The new number of rows.
    public mutating func resize(columns newCols: Int, rows newRows: Int) {
        let safeCols = max(0, newCols)
        let safeRows = max(0, newRows)
        let (capacity, overflow) = safeCols.multipliedReportingOverflow(by: safeRows)
        precondition(!overflow, "ScreenBuffer resize overflows Int: cols=\(newCols), rows=\(newRows)")
        var newCells = ContiguousArray<Cell>(repeating: .empty, count: capacity)
        let copyRows = min(rows, safeRows)
        let copyCols = min(columns, safeCols)
        for r in 0 ..< copyRows {
            for c in 0 ..< copyCols {
                newCells[r * safeCols + c] = cells[r * columns + c]
            }
        }
        self = ScreenBuffer._fromParts(cells: newCells, columns: safeCols, rows: safeRows)
    }

    private static func _fromParts(cells: ContiguousArray<Cell>, columns: Int, rows: Int)
        -> ScreenBuffer
    {
        var buf = ScreenBuffer(columns: columns, rows: rows)
        buf.cells = cells
        // Mark everything dirty after resize (batch operation, O(words) not O(cells))
        buf.dirty.markAll()
        return buf
    }
}
