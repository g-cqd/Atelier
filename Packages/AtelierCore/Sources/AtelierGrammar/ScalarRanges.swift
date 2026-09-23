/// A set of Unicode scalar values, as the sorted, disjoint and non-adjacent closed ranges that make it up.
///
/// The character classes of a token's pattern, and the labels of the lexer automaton's transitions, are sets of this
/// kind; every value lies in `0 ... 0x10FFFF`.
struct ScalarRanges: Sendable, Hashable {
    static let maxScalar: UInt32 = 0x10_FFFF

    static let empty = ScalarRanges(normalized: [])
    static let all = ScalarRanges(normalized: [0 ... maxScalar])

    /// The ranges, sorted, disjoint and never adjacent.
    let ranges: [ClosedRange<UInt32>]

    private init(normalized ranges: [ClosedRange<UInt32>]) {
        self.ranges = ranges
    }

    /// The set of the values in any of `ranges`, which may overlap, touch or come in any order.
    init(_ ranges: [ClosedRange<UInt32>]) {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<UInt32>] = []
        merged.reserveCapacity(sorted.count)
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        self.init(normalized: merged)
    }

    init(scalar: UInt32) {
        self.init(normalized: [scalar ... scalar])
    }

    var isEmpty: Bool { ranges.isEmpty }

    func union(_ other: ScalarRanges) -> ScalarRanges {
        ScalarRanges(ranges + other.ranges)
    }

    /// Every scalar value not in the set.
    func inverted() -> ScalarRanges {
        var result: [ClosedRange<UInt32>] = []
        var next: UInt32 = 0
        for range in ranges {
            if range.lowerBound > next {
                result.append(next ... range.lowerBound - 1)
            }
            guard range.upperBound < Self.maxScalar else { return ScalarRanges(normalized: result) }
            next = range.upperBound + 1
        }
        result.append(next ... Self.maxScalar)
        return ScalarRanges(normalized: result)
    }

    /// - Complexity: O(log r) for r ranges.
    func contains(_ value: UInt32) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < ranges.count && ranges[low].contains(value)
    }
}
