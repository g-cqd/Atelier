/// A rectangular region of the screen in row/column coordinates, the unit of partial repaint.
public struct DirtyRect: Sendable, Equatable, Hashable {
    /// Top row (inclusive).
    public var row: Int
    /// Leftmost column (inclusive).
    public var col: Int
    /// Number of rows (exclusive upper bound = `row + height`).
    public var height: Int
    /// Number of columns (exclusive upper bound = `col + width`).
    public var width: Int

    public init(row: Int, col: Int, height: Int, width: Int) {
        self.row = row
        self.col = col
        self.height = height
        self.width = width
    }

    public var isEmpty: Bool { height <= 0 || width <= 0 }
    public var maxRow: Int { row + height }
    public var maxCol: Int { col + width }

    public func contains(row queryRow: Int, col queryCol: Int) -> Bool {
        queryRow >= row && queryRow < maxRow
            && queryCol >= col && queryCol < maxCol
    }
}

/// The screen regions to repaint on the next frame; rects may overlap, since nothing coalesces them.
public struct DirtyRegions: Sendable, Equatable {
    private var rects: [DirtyRect]

    public init() {
        self.rects = []
    }

    public var isEmpty: Bool { rects.isEmpty }
    public var rectangles: [DirtyRect] { rects }

    /// Marks `rect` as dirty. Empty rectangles are ignored.
    public mutating func mark(_ rect: DirtyRect) {
        guard !rect.isEmpty else { return }
        rects.append(rect)
    }

    /// Convenience for marking a single full-width row dirty.
    public mutating func markRow(_ row: Int, columns: Int) {
        mark(DirtyRect(row: row, col: 0, height: 1, width: columns))
    }

    /// Replaces every rect with one covering the whole buffer, or with none when the buffer is empty.
    public mutating func markAll(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else {
            rects.removeAll(keepingCapacity: true)
            return
        }
        rects = [DirtyRect(row: 0, col: 0, height: rows, width: columns)]
    }

    /// Removes all rectangles.
    public mutating func clear() {
        rects.removeAll(keepingCapacity: true)
    }

    /// Returns `true` when `(row, col)` lies inside at least one rect.
    /// - Complexity: O(n), where n is the number of rects.
    public func contains(row: Int, col: Int) -> Bool {
        for rect in rects where rect.contains(row: row, col: col) {
            return true
        }
        return false
    }

    /// Adds every rect from `other` to `self`.
    public mutating func formUnion(_ other: DirtyRegions) {
        rects.append(contentsOf: other.rects)
    }
}
