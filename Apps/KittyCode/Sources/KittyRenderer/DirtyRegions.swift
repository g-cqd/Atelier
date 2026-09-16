/// A rectangular region of the screen, in row/column coordinates.
///
/// `DirtyRect` is the unit the rendering pipeline operates on for partial
/// repaint: callers describe which area of the screen they want re-painted,
/// and the pipeline limits its work to those areas.
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

/// Set of rectangular regions of the screen that need re-painting on the
/// next frame.
///
/// The pipeline drains and applies these between frames; views and state
/// mutations describe what they changed via `mark(_:)` or `markRow(_:columns:)`.
///
/// Implementation notes — the collection allows overlap (no coalescing yet).
/// Containment queries are linear in the rect count which is fine for typical
/// per-frame workloads (a handful of rects). If profiles show this becoming a
/// hot path we can switch to a segment tree without changing the API.
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

    /// Marks the entire buffer as dirty. Discards any previous rectangles
    /// since a single all-encompassing rect supersedes them.
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
