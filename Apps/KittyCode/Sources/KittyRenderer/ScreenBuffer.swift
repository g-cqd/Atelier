import AtelierText
import KittyCodecs
public import KittyStyle

/// A flat grid of cells representing the terminal screen.
///
/// No cell the diff sends holds a control character: the setter, ``fill(row:col:width:height:cell:)`` and
/// ``write(_:row:col:style:)`` store a C0 control, DEL or a C1 control as ``replacement``, so text such as a file
/// name cannot reach the terminal as a command. A continuation cell keeps its character, which the diff never sends.
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
    /// Out-of-bounds reads return `Cell.empty`; out-of-bounds writes are silently ignored. The setter stores a
    /// control character as ``replacement`` and marks the index dirty only when the stored cell changes.
    public subscript(row: Int, col: Int) -> Cell {
        get {
            guard row >= 0, row < rows, col >= 0, col < columns else { return .empty }
            return cells[row &* columns &+ col]
        }
        set {
            guard row >= 0, row < rows, col >= 0, col < columns else { return }
            let index = row &* columns &+ col
            // No stored cell sends a control, so a cell equal to the stored one needs no check.
            guard cells[index] != newValue else { return }
            if Self.needsReplacement(newValue) {
                var shown = newValue
                shown.character = Self.replacement
                store(shown, at: index)
            } else {
                cells[index] = newValue
                dirty.mark(index)
            }
        }
    }

    /// Writes a string with the given style into the buffer starting at the specified position.
    ///
    /// Wide characters (CJK, fullwidth) occupy two columns. A continuation cell is placed
    /// in the second column. Characters that would extend past the buffer edge are dropped, and a control character
    /// is written as ``replacement``.
    ///
    /// - Parameters:
    ///   - string: The text to write.
    ///   - row: The zero-based row index at which to begin writing.
    ///   - col: The zero-based column index at which to begin writing.
    ///   - style: The visual style to apply to every character in `string`.
    /// - Complexity: O(n) in the UTF-8 length of `string`; printable ASCII skips grapheme breaking and width lookup.
    public mutating func write(_ string: String, row: Int, col: Int, style: Style) {
        guard row >= 0, row < rows, col >= 0 else { return }
        let base = row &* columns
        var c = col
        let text = string.utf8Span
        let bytes = text.span
        var characters = text.makeCharacterIterator()
        var offset = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            let next = offset &+ 1
            // Printable ASCII followed by ASCII, or by nothing, is a one-column character of its own.
            if byte &- 0x20 < 0x5F, next == bytes.count || bytes[next] < 0x80 {
                guard c < columns else { return }
                storeNarrow(Character(Unicode.Scalar(byte)), style: style, at: base, column: c)
                c &+= 1
                offset = next
                continue
            }
            if characters.currentCodeUnitOffset != offset {
                characters.reset(roundingForwardsFrom: offset)
            }
            guard let raw = characters.next() else { return }
            offset = characters.currentCodeUnitOffset
            let char = Self.isControl(raw) ? Self.replacement : raw
            let w = UnicodeWidth.displayWidth(of: char)
            guard w > 0 else { continue }
            if w == 2 {
                guard c + 1 < columns else { return }
                store(Cell(character: char, style: style, width: 2), at: base &+ c)
                store(Cell(character: "\0", style: style, width: 0), at: base &+ c &+ 1)
                c += 2
            } else {
                guard c < columns else { return }
                storeNarrow(char, style: style, at: base, column: c)
                c += 1
            }
        }
    }

    /// The glyph a control character is shown as.
    public static let replacement: Character = "\u{FFFD}"

    /// Whether `character` carries a C0 control, DEL or a C1 control, per `TextSanitizer.isControl(_:)`.
    /// - Complexity: O(1) for ASCII, otherwise O(n) in the scalars of `character`.
    @inline(__always)
    public static func isControl(_ character: Character) -> Bool {
        // ASCII, the common case, is a single byte, so it needs no scalar decoding.
        let utf8 = character.utf8
        if utf8.count == 1, let byte = utf8.first {
            return TextSanitizer.isControl(Unicode.Scalar(byte))
        }
        return character.unicodeScalars.contains(where: TextSanitizer.isControl)
    }

    /// Whether storing `cell` as it is would send a control character: its character is one, and it is not a
    /// continuation cell, whose character the diff never sends.
    @inline(__always)
    static func needsReplacement(_ cell: Cell) -> Bool {
        cell.width != 0 && isControl(cell.character)
    }

    /// Stores `cell`, which holds no control character unless it is a continuation, and marks its index dirty when
    /// that changes the cell.
    @inline(__always)
    private mutating func store(_ cell: Cell, at index: Int) {
        guard cells[index] != cell else { return }
        cells[index] = cell
        dirty.mark(index)
    }

    /// Stores a one-column `character`, free of controls, at `column` of the row starting at `base`, and clears the
    /// continuation cell after it, which lost the wide character it belonged to.
    @inline(__always)
    private mutating func storeNarrow(_ character: Character, style: Style, at base: Int, column: Int) {
        store(Cell(character: character, style: style, width: 1), at: base &+ column)
        let after = column &+ 1
        if after < columns, cells[base &+ after].width == 0 {
            store(.empty, at: base &+ after)
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
    /// The region is clamped to the buffer bounds. Out-of-bounds or zero-area rectangles are ignored. A control
    /// character in `cell` is stored as ``replacement``.
    ///
    /// - Parameters:
    ///   - row: The zero-based row index of the top-left corner.
    ///   - col: The zero-based column index of the top-left corner.
    ///   - width: The number of columns to fill.
    ///   - height: The number of rows to fill.
    ///   - cell: The cell value to write into every position in the rectangle.
    public mutating func fill(row: Int, col: Int, width: Int, height: Int, cell: Cell) {
        guard row >= 0, row < rows, col >= 0, col < columns, width > 0, height > 0 else { return }
        var shown = cell
        if Self.needsReplacement(shown) {
            shown.character = Self.replacement
        }
        let rowEnd = row + min(height, rows - row)
        let colEnd = col + min(width, columns - col)
        for r in row ..< rowEnd {
            let base = r &* columns
            for c in col ..< colEnd {
                store(shown, at: base &+ c)
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
        guard delta != 0, regionWidth > 0, regionHeight > 0, abs(delta) < regionHeight,
            regionY >= 0, regionX >= 0, regionY + regionHeight <= rows, regionX + regionWidth <= columns
        else {
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

    /// Copies cells marked dirty in `source` into this buffer without sharing either grid's storage.
    /// - Precondition: Both buffers have the same dimensions.
    /// - Complexity: O(columns × rows) time; O(1) extra space with unique storage, otherwise O(columns × rows).
    mutating func adoptDirtyCells(from source: ScreenBuffer) {
        precondition(columns == source.columns && rows == source.rows, "ScreenBuffer dimensions differ")
        let sourceCells = source.cells.span
        var destination = cells.mutableSpan
        for index in 0 ..< destination.count where source.dirty.isDirty(index) {
            destination[index] = sourceCells[index]
        }
    }

    /// Copies every cell after a forced redraw without sharing either grid's storage.
    /// - Precondition: Both buffers have the same dimensions.
    /// - Complexity: O(columns × rows) time; O(1) extra space with unique storage, otherwise O(columns × rows).
    mutating func adoptAllCells(from source: ScreenBuffer) {
        precondition(columns == source.columns && rows == source.rows, "ScreenBuffer dimensions differ")
        let sourceCells = source.cells.span
        var destination = cells.mutableSpan
        for index in 0 ..< destination.count {
            destination[index] = sourceCells[index]
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
