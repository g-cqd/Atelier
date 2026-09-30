/// Row heights with O(log rows) prefix queries, backed by a Fenwick (binary-indexed) tree over the rows' current
/// heights (text-renderer.md §3.3). Every row starts exact when lines never wrap, since every row is then one line of
/// the configured height; with wrapping, a row starts estimated from its display width in cells, and stays estimated
/// until a typeset pass corrects it.
public struct HeightIndex: Sendable {
    /// 1-indexed Fenwick tree of size `n + 1`; `tree[0]` is unused.
    private var tree: [Float]
    private var heights: [Float]
    private var exactFlags: [Bool]
    private let rowCount: Int

    public init(text: StyledText, configuration: LayoutConfiguration, cellAdvance: Double) {
        rowCount = text.rowCount
        let lineHeight = Float(configuration.resolvedLineHeight)
        var initial = [Float](repeating: lineHeight, count: rowCount)
        var exact = [Bool](repeating: true, count: rowCount)
        if configuration.wrap != .none {
            let columns = Self.columns(configuration: configuration, cellAdvance: cellAdvance)
            if columns > 0 {
                for index in 0 ..< rowCount {
                    let cells = Self.estimatedCells(
                        bytes: text.bytes(ofRow: RowIndex(index)), tabWidth: configuration.tabWidth)
                    let lines = max(1, Int((Double(cells) / Double(columns)).rounded(.up)))
                    initial[index] = lineHeight * Float(lines)
                    exact[index] = lines <= 1
                }
            }
        }
        heights = initial
        exactFlags = exact
        tree = [Float](repeating: 0, count: rowCount + 1)
        for index in 0 ..< rowCount { Self.add(&tree, at: index, delta: initial[index]) }
    }

    /// The available columns a row wraps at: the configured column count, or the viewport width divided by the
    /// advance of one cell.
    private static func columns(configuration: LayoutConfiguration, cellAdvance: Double) -> Int {
        switch configuration.wrap {
            case .none: 0
            case .columns(let count): count
            case .width(let width): cellAdvance > 0 ? max(1, Int(width / cellAdvance)) : 0
        }
    }

    /// The row's width in cells: every scalar one cell, a tab ``LayoutConfiguration/tabWidth``. An estimate, not a
    /// grapheme-accurate or double-width-aware measurement (text-renderer.md §3.3); a typeset pass corrects it.
    private static func estimatedCells(bytes: ArraySlice<UInt8>, tabWidth: Int) -> Int {
        var cells = 0
        for byte in bytes where byte & 0xC0 != 0x80 {
            cells += byte == 0x09 ? tabWidth : 1
        }
        return cells
    }

    public var documentHeight: Double { Double(Self.sum(tree, upTo: rowCount)) }

    /// - Complexity: O(log rows)
    public func y(of row: RowIndex) -> Double { Double(Self.sum(tree, upTo: min(row.index, rowCount))) }

    /// - Complexity: O(log rows)
    public func row(atY y: Double) -> RowIndex {
        guard rowCount > 0 else { return RowIndex(0) }
        var index = 0
        var remaining = Float(max(y, 0))
        var bitMask = 1
        while (bitMask << 1) <= rowCount { bitMask <<= 1 }
        while bitMask > 0 {
            let next = index + bitMask
            if next <= rowCount, tree[next] <= remaining {
                index = next
                remaining -= tree[next]
            }
            bitMask >>= 1
        }
        return RowIndex(min(index, rowCount - 1))
    }

    public func isExact(_ row: RowIndex) -> Bool {
        exactFlags.indices.contains(row.index) ? exactFlags[row.index] : true
    }

    /// - Returns: the height change, for scroll anchoring.
    public mutating func setHeight(_ height: Float, of row: RowIndex) -> Double {
        let index = row.index
        guard heights.indices.contains(index) else { return 0 }
        let delta = height - heights[index]
        heights[index] = height
        exactFlags[index] = true
        if delta != 0 { Self.add(&tree, at: index, delta: delta) }
        return Double(delta)
    }

    public func height(of row: RowIndex) -> Float { heights.indices.contains(row.index) ? heights[row.index] : 0 }

    // MARK: Fenwick tree primitives (0-based row indices, 1-based tree positions)

    private static func add(_ tree: inout [Float], at index0: Int, delta: Float) {
        var position = index0 + 1
        while position < tree.count {
            tree[position] += delta
            position += position & (-position)
        }
    }

    /// Sum of the first `count` rows' heights (rows `0 ..< count`).
    private static func sum(_ tree: [Float], upTo count: Int) -> Float {
        var position = count
        var total: Float = 0
        while position > 0 {
            total += tree[position]
            position -= position & (-position)
        }
        return total
    }
}
