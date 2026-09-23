/// One entry of an edit script, in output order.
public enum DiffEdit: Equatable, Sendable {
    case equal(old: Int, new: Int)
    case delete(old: Int)
    case insert(new: Int)
}

/// Produces an edit script between two interned line sequences.
public protocol LineDiffing: Sendable {
    func diff(_ old: [Int], _ new: [Int]) -> [DiffEdit]
}

/// Adjusts an edit script without changing what it reconstructs, using the line text for its judgement.
public protocol EditScriptRefining: Sendable {
    func refine(_ edits: [DiffEdit], lines: LineDiffContext) -> [DiffEdit]
}

/// What refiners may look at: the interned ids and the leading indentation of every line on both sides.
public struct LineDiffContext: Sendable {
    public let old: [Int]
    public let new: [Int]
    /// Leading whitespace width per line, tabs to the next multiple of eight; nil for a blank line.
    public let oldIndents: [Int?]
    public let newIndents: [Int?]

    public init(old: [Int], new: [Int], oldIndents: [Int?], newIndents: [Int?]) {
        self.old = old
        self.new = new
        self.oldIndents = oldIndents
        self.newIndents = newIndents
    }
}

/// Shortest edit script: linear-space Myers ("An O(ND) Difference Algorithm and Its Variations", section 4b) over the
/// lines both sides share, with git's cost limit, past which the script stays valid but may not be the shortest.
/// - Complexity: O((N + M) * D) time and O(N + M) space, where D is the size of the edit script; a search stops
///   after about 4√(N + M) rounds.
public struct MyersLineDiff: LineDiffing {
    public init() {}

    public func diff(_ old: [Int], _ new: [Int]) -> [DiffEdit] {
        LineDiff.diff(old, new, anchoringRareLines: false)
    }
}

/// Git's `histogram` algorithm: the rarest lines common to both sides are matched first and anchor the alignment,
/// Myers fills the stretches between anchors. Anchoring keeps repetitive lines (braces, blank lines) from being
/// matched across unrelated regions, which is where a plain shortest edit script reads wrong.
public struct HistogramLineDiff: LineDiffing {
    public init() {}

    public func diff(_ old: [Int], _ new: [Int]) -> [DiffEdit] {
        LineDiff.diff(old, new, anchoringRareLines: true)
    }
}

public enum LineDiff {
    /// Lines occurring more often than this on the old side are never anchors; JGit's limit.
    static let maximumAnchorOccurrences = 64

    /// Shared prefix and suffix are matched directly; the middle goes to the histogram anchoring or to Myers.
    ///
    /// Myers sets aside the lines that occur on one side only, which can never match, and stops looking for the
    /// shortest script once its search passes ``costLimit(lines:)``, splitting the problem heuristically instead, as
    /// git does. A task cancelled while it runs gets a valid script that is not the shortest: the search stops within
    /// 64 rounds and whatever is left is deleted and inserted whole.
    public static func diff<Element: Hashable>(_ old: [Element], _ new: [Element], anchoringRareLines: Bool = true)
        -> [DiffEdit]
    {
        diff(old, new, anchoringRareLines: anchoringRareLines, costLimit: nil)
    }

    /// ``diff(_:_:anchoringRareLines:)`` with `costLimit`, when given, in place of every search's own limit.
    static func diff<Element: Hashable>(
        _ old: [Element], _ new: [Element], anchoringRareLines: Bool, costLimit: Int?
    ) -> [DiffEdit] {
        var edits: [DiffEdit] = []
        edits.reserveCapacity(max(old.count, new.count))
        let middle = matchEnds(old, new, into: &edits)
        if anchoringRareLines {
            var histogram = HistogramSolver(old: old, new: new, costLimit: costLimit)
            histogram.solve(old: middle.old, new: middle.new, into: &edits)
        } else {
            _ = solveMatched(old, middle.old, new, middle.new, costLimit: costLimit, into: &edits)
        }
        for offset in 0 ..< (old.count - middle.old.upperBound) {
            edits.append(.equal(old: middle.old.upperBound + offset, new: middle.new.upperBound + offset))
        }
        return edits
    }

    /// The shortest edit script when it holds at most `maximumEdits` edits, else nil, as it is when the task is
    /// cancelled. The search gives up in the round that proves the script longer, so a pair too different to be worth
    /// it costs a fraction of a full diff.
    static func diff<Element: Hashable>(_ old: [Element], _ new: [Element], maximumEdits: Int) -> [DiffEdit]? {
        var edits: [DiffEdit] = []
        let middle = matchEnds(old, new, into: &edits)
        // With a side empty, the script deletes or inserts the other one whole, and no search runs.
        if middle.old.isEmpty || middle.new.isEmpty, middle.old.count + middle.new.count > maximumEdits { return nil }
        // No cost limit: every snake is then exact, so the first one tells the cost of the whole script.
        var solver = MyersSolver(old: old, new: new, costLimit: .max, maximumEdits: maximumEdits)
        solver.solve(old: middle.old, new: middle.new, into: &edits)
        guard !solver.exceededBudget, !solver.wasCancelled else { return nil }
        for offset in 0 ..< (old.count - middle.old.upperBound) {
            edits.append(.equal(old: middle.old.upperBound + offset, new: middle.new.upperBound + offset))
        }
        return edits
    }

    /// Rounds a middle-snake search over `lines` lines on both sides may take before it settles for a heuristic
    /// split: four times the square root of the problem size, and never fewer than 256, as git's `mxcost`.
    static func costLimit(lines: Int) -> Int {
        max(256, 4 * Int(Double(lines).squareRoot()))
    }

    /// Where Myers splits a problem of `n` old and `m` new lines once its search reaches the cost limit in round `d`:
    /// at the point furthest along round `d - 1`'s forward paths, by x + y, whose diagonal stays in the problem, where
    /// `reach(k)` is the x that round reached on diagonal `k`; or, when that point is a corner, at an inner point,
    /// since a split at (0, 0) or (n, m) would hand the same problem back. git's `xdl_split` heuristic as perf-core
    /// corrected it, with a fallback that stays inner for a 1 by 1 problem too.
    static func costLimitedSplit(round d: Int, n: Int, m: Int, reach: (Int) -> Int) -> (x: Int, y: Int) {
        var bestK = 1 - d
        var bestReach = -1
        for k in stride(from: 1 - d, through: d - 1, by: 2) {
            let x = min(reach(k), n)
            let y = x - k
            if y >= 0, y <= m, x + y > bestReach {
                bestReach = x + y
                bestK = k
            }
        }
        let x = min(reach(bestK), n)
        let y = max(0, min(m, x - bestK))
        guard x + y == 0 || (x == n && y == m) else { return (x, y) }
        return ((n + 1) / 2, m / 2)
    }

    /// Appends the shared prefix as equal lines and returns the ranges left between it and the shared suffix.
    private static func matchEnds<Element: Equatable>(_ old: [Element], _ new: [Element], into edits: inout [DiffEdit])
        -> (old: Range<Int>, new: Range<Int>)
    {
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            edits.append(.equal(old: prefix, new: prefix))
            prefix += 1
        }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > prefix, newEnd > prefix, old[oldEnd - 1] == new[newEnd - 1] {
            oldEnd -= 1
            newEnd -= 1
        }
        return (prefix ..< oldEnd, prefix ..< newEnd)
    }

    /// Myers over the lines of the two ranges that occur on both sides, the others put back as deletions and
    /// insertions where they fall. A line found on one side only can never be matched, so setting it aside leaves the
    /// shortest script as short as it was while the search runs on a smaller problem; git's `xdl_cleanup_records`.
    /// - Returns: Whether a cancellation stopped the search.
    fileprivate static func solveMatched<Element: Hashable>(
        _ old: [Element], _ oldRange: Range<Int>, _ new: [Element], _ newRange: Range<Int>, costLimit: Int?,
        into edits: inout [DiffEdit]
    ) -> Bool {
        let (keptOld, keptNew) = matchedPositions(old, oldRange, new, newRange)
        var solver = MyersSolver(
            old: keptOld.map { old[$0] }, new: keptNew.map { new[$0] },
            costLimit: costLimit ?? Self.costLimit(lines: keptOld.count + keptNew.count))
        var kept: [DiffEdit] = []
        kept.reserveCapacity(keptOld.count + keptNew.count)
        solver.solve(old: 0 ..< keptOld.count, new: 0 ..< keptNew.count, into: &kept)

        // Each set-aside line goes in just before the first kept line that follows it on its side.
        var oldIndex = oldRange.lowerBound
        var newIndex = newRange.lowerBound
        for edit in kept {
            switch edit {
                case .equal(let oldKept, let newKept):
                    while oldIndex < keptOld[oldKept] {
                        edits.append(.delete(old: oldIndex))
                        oldIndex += 1
                    }
                    while newIndex < keptNew[newKept] {
                        edits.append(.insert(new: newIndex))
                        newIndex += 1
                    }
                    edits.append(.equal(old: oldIndex, new: newIndex))
                    oldIndex += 1
                    newIndex += 1
                case .delete(let oldKept):
                    while oldIndex <= keptOld[oldKept] {
                        edits.append(.delete(old: oldIndex))
                        oldIndex += 1
                    }
                case .insert(let newKept):
                    while newIndex <= keptNew[newKept] {
                        edits.append(.insert(new: newIndex))
                        newIndex += 1
                    }
            }
        }
        for index in oldIndex ..< oldRange.upperBound { edits.append(.delete(old: index)) }
        for index in newIndex ..< newRange.upperBound { edits.append(.insert(new: index)) }
        return solver.wasCancelled
    }

    /// The positions in `oldRange` whose line also occurs in `newRange`, and the other way round.
    private static func matchedPositions<Element: Hashable>(
        _ old: [Element], _ oldRange: Range<Int>, _ new: [Element], _ newRange: Range<Int>
    ) -> (old: [Int], new: [Int]) {
        // Interned lines are small integers: marking them in two arrays costs a fraction of hashing them into sets,
        // which would be most of this pass on a large diff. Where `Element` is `Int` the casts compile away.
        if let oldIdentifiers = old as? [Int], let newIdentifiers = new as? [Int],
            let matched = denseMatchedPositions(oldIdentifiers, oldRange, newIdentifiers, newRange)
        {
            return matched
        }
        let onOld = Set(old[oldRange])
        let onNew = Set(new[newRange])
        return (oldRange.filter { onNew.contains(old[$0]) }, newRange.filter { onOld.contains(new[$0]) })
    }

    /// ``matchedPositions(_:_:_:_:)`` over identifiers marked in arrays, or nil when one is negative or too large for
    /// an array about the size of the ranges, as a stretch of a larger diff can hold.
    private static func denseMatchedPositions(
        _ old: [Int], _ oldRange: Range<Int>, _ new: [Int], _ newRange: Range<Int>
    ) -> (old: [Int], new: [Int])? {
        let bound = 2 * (oldRange.count + newRange.count) + 1_024
        guard old[oldRange].allSatisfy({ (0 ..< bound).contains($0) }),
            new[newRange].allSatisfy({ (0 ..< bound).contains($0) })
        else { return nil }
        var onOld = [Bool](repeating: false, count: bound)
        var onNew = onOld
        for index in oldRange { onOld[old[index]] = true }
        for index in newRange { onNew[new[index]] = true }
        return (oldRange.filter { onNew[old[$0]] }, newRange.filter { onOld[new[$0]] })
    }

    /// Diffs lines through `pipeline`: interned so each comparison in the inner loop is an integer comparison,
    /// then refined by every stage the pipeline wires in.
    public static func diffLines(_ old: [Substring], _ new: [Substring], pipeline: DiffPipeline = DiffPipeline())
        -> [DiffEdit]
    {
        diffLines(old: SubstringLines(old), new: SubstringLines(new), pipeline: pipeline)
    }

    /// The edit script between two line sources: lines are interned under the pipeline's whitespace mode, the
    /// line diff runs over the identifiers, and the refiners see the indents measured on the bytes.
    /// - Complexity: O(bytes) to intern, plus the line diff's own cost.
    public static func diffLines(old: some DiffSource, new: some DiffSource, pipeline: DiffPipeline = DiffPipeline())
        -> [DiffEdit]
    {
        var interner = LineInterner(whitespace: pipeline.whitespace)
        let oldLines = interner.intern(old)
        let newLines = interner.intern(new)
        let context = LineDiffContext(
            old: oldLines.identifiers, new: newLines.identifiers, oldIndents: oldLines.indents,
            newIndents: newLines.indents)
        var edits = pipeline.lineDiff.diff(context.old, context.new)
        for refiner in pipeline.refiners {
            edits = refiner.refine(edits, lines: context)
        }
        return edits
    }

    /// Leading whitespace width with tabs to the next multiple of eight, or nil for a blank line; git's `get_indent`.
    static func indent(of line: Substring) -> Int? {
        line.utf8.withContiguousStorageIfAvailable { unsafe indent(of: Span(_unsafeElements: $0)) }
            ?? indent(of: Array(line.utf8).span)
    }

    static func indent(of line: Span<UInt8>) -> Int? {
        var width = 0
        for index in 0 ..< line.count {
            let byte = line[index]
            switch byte {
                case UInt8(ascii: " "): width += 1
                case UInt8(ascii: "\t"): width += 8 - width % 8
                case UInt8(ascii: "\r"), UInt8(ascii: "\u{0C}"), UInt8(ascii: "\u{0B}"): continue
                default: return min(width, IndentHeuristic.maximumIndent)
            }
        }
        return nil
    }
}

/// Matches the rarest common elements first, recursing on both sides of each anchor; stretches with no rare
/// common element fall back to Myers. Mirrors JGit's `HistogramDiff`.
private struct HistogramSolver<Element: Hashable> {
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

/// Linear-space Myers ("An O(ND) Difference Algorithm and Its Variations", section 4b) with git's cost limit: a
/// middle-snake search that passes `costLimit` rounds splits its problem heuristically instead of finding the middle.
private struct MyersSolver<Element: Equatable> {
    private enum Work {
        case solve(old: Range<Int>, new: Range<Int>)
        case equal(old: Int, new: Int, count: Int)
    }

    private struct Snake {
        let x: Int
        let y: Int
        let u: Int
        let v: Int
        let edits: Int
    }

    /// How a middle-snake search ended.
    private enum Search {
        case found(Snake)
        /// The task was cancelled: the search stopped without a split, which in round 0 would make no progress.
        case cancelled
        /// The script is longer than `maximumEdits`.
        case overBudget
    }

    private let old: [Element]
    private let new: [Element]
    private var forward: [Int]
    private var backward: [Int]
    private let offset: Int
    private let costLimit: Int
    private let maximumEdits: Int
    /// Set once a cancellation stopped a search: every problem left is then deleted and inserted whole, a valid
    /// script if not the shortest.
    private(set) var wasCancelled = false
    /// Set when the script proved longer than `maximumEdits`; the edits appended so far are then incomplete.
    private(set) var exceededBudget = false

    init(old: [Element], new: [Element], costLimit: Int, maximumEdits: Int = .max) {
        self.old = old
        self.new = new
        let maximum = (old.count + new.count + 1) / 2 + 1
        offset = maximum + 1
        forward = Array(repeating: 0, count: 2 * maximum + 3)
        backward = forward
        self.costLimit = costLimit
        self.maximumEdits = maximumEdits
    }

    mutating func solve(old oldRange: Range<Int>, new newRange: Range<Int>, into edits: inout [DiffEdit]) {
        var stack: [Work] = [.solve(old: oldRange, new: newRange)]

        while let work = stack.popLast() {
            switch work {
                case .equal(let oldStart, let newStart, let count):
                    for index in 0 ..< count {
                        edits.append(.equal(old: oldStart + index, new: newStart + index))
                    }

                case .solve(let oldRange, let newRange):
                    if oldRange.isEmpty || newRange.isEmpty || wasCancelled {
                        for index in oldRange { edits.append(.delete(old: index)) }
                        for index in newRange { edits.append(.insert(new: index)) }
                        continue
                    }

                    let snake: Snake
                    switch middleSnake(old: oldRange, new: newRange) {
                        case .found(let found): snake = found
                        case .cancelled:
                            wasCancelled = true
                            stack.append(.solve(old: oldRange, new: newRange))
                            continue
                        case .overBudget:
                            exceededBudget = true
                            return
                    }
                    if snake.edits > maximumEdits {
                        exceededBudget = true
                        return
                    }
                    if snake.edits > 1 {
                        stack.append(
                            .solve(
                                old: (oldRange.lowerBound + snake.u) ..< oldRange.upperBound,
                                new: (newRange.lowerBound + snake.v) ..< newRange.upperBound
                            ))
                        stack.append(
                            .equal(
                                old: oldRange.lowerBound + snake.x,
                                new: newRange.lowerBound + snake.y,
                                count: snake.u - snake.x
                            ))
                        stack.append(
                            .solve(
                                old: oldRange.lowerBound ..< (oldRange.lowerBound + snake.x),
                                new: newRange.lowerBound ..< (newRange.lowerBound + snake.y)
                            ))
                    } else {
                        appendTrivial(old: oldRange, new: newRange, into: &edits)
                    }
            }
        }
    }

    /// Handles an edit script of size at most one: the shorter side is entirely contained in the longer one.
    private func appendTrivial(old oldRange: Range<Int>, new newRange: Range<Int>, into edits: inout [DiffEdit]) {
        let n = oldRange.count
        let m = newRange.count
        let common = min(n, m)
        var index = 0
        while index < common, old[oldRange.lowerBound + index] == new[newRange.lowerBound + index] {
            edits.append(.equal(old: oldRange.lowerBound + index, new: newRange.lowerBound + index))
            index += 1
        }
        if m > n {
            edits.append(.insert(new: newRange.lowerBound + index))
        } else if n > m {
            edits.append(.delete(old: oldRange.lowerBound + index))
        }
        let oldRest = oldRange.lowerBound + index + (n > m ? 1 : 0)
        let newRest = newRange.lowerBound + index + (m > n ? 1 : 0)
        for rest in 0 ..< (common - index) {
            edits.append(.equal(old: oldRest + rest, new: newRest + rest))
        }
    }

    private mutating func middleSnake(old oldRange: Range<Int>, new newRange: Range<Int>) -> Search {
        let n = oldRange.count
        let m = newRange.count
        let delta = n - m
        let isOdd = delta & 1 != 0
        let maximum = (n + m + 1) / 2 + 1

        forward[offset + 1] = 0
        backward[offset + 1] = 0

        for d in 0 ... maximum {
            // Read from synchronous code running in a task; never in round 0, where every search would stop.
            if d > 0, d & 63 == 0, Task.isCancelled { return .cancelled }
            // No round before this one met the other search, so the script holds at least 2d - 1 edits.
            if 2 * d - 1 > maximumEdits { return .overBudget }
            if d >= costLimit {
                let split = LineDiff.costLimitedSplit(round: d, n: n, m: m) { forward[offset + $0] }
                return .found(Snake(x: split.x, y: split.y, u: split.x, v: split.y, edits: 2 * d))
            }

            var k = -d
            while k <= d {
                var x =
                    if k == -d || (k != d && forward[offset + k - 1] < forward[offset + k + 1]) {
                        forward[offset + k + 1]
                    } else {
                        forward[offset + k - 1] + 1
                    }
                var y = x - k
                let startX = x
                let startY = y
                while x < n, y < m, old[oldRange.lowerBound + x] == new[newRange.lowerBound + y] {
                    x += 1
                    y += 1
                }
                forward[offset + k] = x

                if isOdd {
                    let backwardK = delta - k
                    if backwardK >= -(d - 1), backwardK <= d - 1, x + backward[offset + backwardK] >= n {
                        return .found(Snake(x: startX, y: startY, u: x, v: y, edits: 2 * d - 1))
                    }
                }
                k += 2
            }

            k = -d
            while k <= d {
                var x =
                    if k == -d || (k != d && backward[offset + k - 1] < backward[offset + k + 1]) {
                        backward[offset + k + 1]
                    } else {
                        backward[offset + k - 1] + 1
                    }
                var y = x - k
                let startX = x
                let startY = y
                while x < n, y < m, old[oldRange.upperBound - 1 - x] == new[newRange.upperBound - 1 - y] {
                    x += 1
                    y += 1
                }
                backward[offset + k] = x

                if !isOdd {
                    let forwardK = delta - k
                    if forwardK >= -d, forwardK <= d, x + forward[offset + forwardK] >= n {
                        return .found(Snake(x: n - x, y: m - y, u: n - startX, v: m - startY, edits: 2 * d))
                    }
                }
                k += 2
            }
        }

        preconditionFailure("Myers middle snake search must terminate within (N + M + 1) / 2 + 1 iterations")
    }
}
