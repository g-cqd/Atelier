/// Bitset-based dirty region tracker for screen buffer.
public struct DirtyTracker: Sendable, Equatable {
    private var bits: [UInt64]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        let words = (capacity + 63) / 64
        self.bits = [UInt64](repeating: 0, count: words)
    }

    public mutating func mark(_ index: Int) {
        guard index >= 0, index < capacity else { return }
        let word = index / 64
        let bit = index % 64
        bits[word] |= (1 << bit)
    }

    /// Marks all cells dirty in a single pass (O(words) instead of O(cells)).
    public mutating func markAll() {
        for i in bits.indices {
            bits[i] = UInt64.max
        }
    }

    public func isDirty(_ index: Int) -> Bool {
        guard index >= 0, index < capacity else { return false }
        let word = index / 64
        let bit = index % 64
        return (bits[word] & (1 << bit)) != 0
    }

    public mutating func clear() {
        for i in bits.indices {
            bits[i] = 0
        }
    }

    public var isEmpty: Bool {
        bits.allSatisfy { $0 == 0 }
    }

    /// Returns ranges of contiguous dirty cells per row.
    public func dirtyRanges(columns: Int) -> [(row: Int, colStart: Int, colEnd: Int)] {
        guard columns > 0 else { return [] }
        var ranges: [(row: Int, colStart: Int, colEnd: Int)] = []
        let rows = capacity / columns

        for row in 0..<rows {
            var colStart: Int? = nil
            for col in 0..<columns {
                let idx = row * columns + col
                if isDirty(idx) {
                    if colStart == nil { colStart = col }
                } else {
                    if let start = colStart {
                        ranges.append((row: row, colStart: start, colEnd: col))
                        colStart = nil
                    }
                }
            }
            if let start = colStart {
                ranges.append((row: row, colStart: start, colEnd: columns))
            }
        }
        return ranges
    }
}
