/// Bitset-based dirty region tracker for screen buffer.
public struct DirtyTracker: Sendable, Equatable {
    private var bits: ContiguousArray<UInt64>
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = capacity
        let words = (capacity + 63) / 64
        self.bits = ContiguousArray<UInt64>(repeating: 0, count: words)
    }

    public mutating func mark(_ index: Int) {
        guard index >= 0, index < capacity else { return }
        let word = index >> 6  // / 64
        let bit = index & 63  // % 64
        bits[word] |= (1 &<< bit)
    }

    /// Marks a contiguous range of indices dirty.
    public mutating func markRange(_ range: Range<Int>) {
        let lo = max(range.lowerBound, 0)
        let hi = min(range.upperBound, capacity)
        guard lo < hi else { return }

        let firstWord = lo >> 6
        let lastWord = (hi - 1) >> 6
        let firstBit = lo & 63
        let lastBit = (hi - 1) & 63

        if firstWord == lastWord {
            let mask = (UInt64.max << firstBit) & (UInt64.max >> (63 - lastBit))
            bits[firstWord] |= mask
        } else {
            bits[firstWord] |= (UInt64.max << firstBit)
            for w in (firstWord + 1) ..< lastWord {
                bits[w] = UInt64.max
            }
            bits[lastWord] |= (UInt64.max >> (63 - lastBit))
        }
    }

    /// Marks all cells dirty in a single pass (O(words) instead of O(cells)).
    public mutating func markAll() {
        bits.withUnsafeMutableBufferPointer { buf in
            buf.update(repeating: UInt64.max)
        }
    }

    public func isDirty(_ index: Int) -> Bool {
        guard index >= 0, index < capacity else { return false }
        let word = index >> 6
        let bit = index & 63
        return (bits[word] & (1 &<< bit)) != 0
    }

    public mutating func clear() {
        bits.withUnsafeMutableBufferPointer { buf in
            buf.update(repeating: 0)
        }
    }

    public var isEmpty: Bool {
        // OR-reduce all words — any non-zero means dirty cells exist
        bits.withUnsafeBufferPointer { buf in
            var acc: UInt64 = 0
            for w in buf { acc |= w }
            return acc == 0
        }
    }

    /// Returns ranges of contiguous dirty cells per row using word-level CTZ scanning.
    public func dirtyRanges(columns: Int) -> [(row: Int, colStart: Int, colEnd: Int)] {
        guard columns > 0 else { return [] }
        var ranges: [(row: Int, colStart: Int, colEnd: Int)] = []
        let rows = capacity / columns

        for row in 0 ..< rows {
            let rowStart = row * columns
            var col = 0
            while col < columns {
                let idx = rowStart + col
                let word = idx >> 6
                let bit = idx & 63

                // Fast skip: if the remaining bits in this word are all zero, advance
                let masked = bits[word] >> bit
                if masked == 0 {
                    // Skip to next word boundary
                    let remaining = 64 - bit
                    col += remaining
                    continue
                }

                // Find first set bit from current position
                let offset = masked.trailingZeroBitCount
                if col + offset >= columns {
                    break
                }
                let dirtyStart = col + offset
                col = dirtyStart

                // Find end of dirty run
                while col < columns {
                    let idx2 = rowStart + col
                    let w2 = idx2 >> 6
                    let b2 = idx2 & 63
                    if (bits[w2] & (1 &<< b2)) == 0 { break }
                    col += 1
                }

                ranges.append((row: row, colStart: dirtyStart, colEnd: col))
            }
        }
        return ranges
    }
}
