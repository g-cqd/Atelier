/// Matches the rarest common elements first, recursing on both sides of each anchor; stretches with no rare
/// common element fall back to Myers. Mirrors JGit's `HistogramDiff`.
struct HistogramSolver<Element: Hashable> {
    private let old: [Element]
    private let new: [Element]
    private let costLimit: Int?
    /// Set once a cancellation stopped a Myers search: every stretch left is then deleted and inserted whole.
    private var wasCancelled = false

    init(old: [Element], new: [Element], costLimit: Int?) {
        self.old = old
        self.new = new
        self.costLimit = costLimit
    }

    private struct Anchor {
        var oldStart: Int
        var newStart: Int
        var length: Int
        /// Highest occurrence count among the anchored lines; lower is rarer.
        var occurrences: Int
    }

    /// Anchors split ranges recursively; results must come out in order, so each split pushes right, anchor, left.
    private enum Work {
        case ranges(Range<Int>, Range<Int>)
        case equal(oldStart: Int, newStart: Int, count: Int)
    }

    mutating func solve(old oldRange: Range<Int>, new newRange: Range<Int>, into edits: inout [DiffEdit]) {
        var work: [Work] = [.ranges(oldRange, newRange)]
        while let item = work.popLast() {
            switch item {
                case .equal(let oldStart, let newStart, let count):
                    for index in 0 ..< count { edits.append(.equal(old: oldStart + index, new: newStart + index)) }
                case .ranges(let oldRange, let newRange):
                    if oldRange.isEmpty || newRange.isEmpty || wasCancelled {
                        for index in oldRange { edits.append(.delete(old: index)) }
                        for index in newRange { edits.append(.insert(new: index)) }
                    } else if let anchor = bestAnchor(old: oldRange, new: newRange) {
                        work.append(
                            .ranges(
                                (anchor.oldStart + anchor.length) ..< oldRange.upperBound,
                                (anchor.newStart + anchor.length) ..< newRange.upperBound))
                        work.append(.equal(oldStart: anchor.oldStart, newStart: anchor.newStart, count: anchor.length))
                        work.append(
                            .ranges(oldRange.lowerBound ..< anchor.oldStart, newRange.lowerBound ..< anchor.newStart))
                    } else {
                        wasCancelled = LineDiff.solveMatched(
                            old, oldRange, new, newRange, costLimit: costLimit, into: &edits)
                    }
            }
        }
    }

    /// The longest run of common lines whose rarest line is as rare as possible, or nil when every common line is
    /// too frequent to anchor on.
    private func bestAnchor(old oldRange: Range<Int>, new newRange: Range<Int>) -> Anchor? {
        var positions: [Element: [Int]] = [:]
        for index in oldRange { positions[old[index], default: []].append(index) }
        var best: Anchor?
        var newIndex = newRange.lowerBound
        while newIndex < newRange.upperBound {
            guard let candidates = positions[new[newIndex]], candidates.count <= LineDiff.maximumAnchorOccurrences
            else {
                newIndex += 1
                continue
            }
            var nextNewIndex = newIndex + 1
            for oldIndex in candidates {
                if let current = best, candidates.count > current.occurrences { break }
                var oldStart = oldIndex
                var newStart = newIndex
                var occurrences = candidates.count
                while oldStart > oldRange.lowerBound, newStart > newRange.lowerBound,
                    old[oldStart - 1] == new[newStart - 1]
                {
                    oldStart -= 1
                    newStart -= 1
                    occurrences = max(occurrences, positions[old[oldStart]]?.count ?? 0)
                }
                var oldEnd = oldIndex + 1
                var newEnd = newIndex + 1
                while oldEnd < oldRange.upperBound, newEnd < newRange.upperBound, old[oldEnd] == new[newEnd] {
                    occurrences = max(occurrences, positions[old[oldEnd]]?.count ?? 0)
                    oldEnd += 1
                    newEnd += 1
                }
                let length = oldEnd - oldStart
                if let current = best {
                    if occurrences < current.occurrences
                        || (occurrences == current.occurrences && length > current.length)
                    {
                        best = Anchor(oldStart: oldStart, newStart: newStart, length: length, occurrences: occurrences)
                    }
                } else {
                    best = Anchor(oldStart: oldStart, newStart: newStart, length: length, occurrences: occurrences)
                }
                nextNewIndex = max(nextNewIndex, newEnd)
            }
            newIndex = nextNewIndex
        }
        return best
    }
}
