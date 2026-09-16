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

/// Shortest edit script: linear-space Myers ("An O(ND) Difference Algorithm and Its Variations", section 4b).
/// - Complexity: O((N + M) * D) time and O(N + M) space, where D is the size of the edit script.
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
    public static func diff<Element: Hashable>(_ old: [Element], _ new: [Element], anchoringRareLines: Bool = true)
        -> [DiffEdit]
    {
        var edits: [DiffEdit] = []
        edits.reserveCapacity(max(old.count, new.count))

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

        var solver = MyersSolver(old: old, new: new)
        if anchoringRareLines {
            var histogram = HistogramSolver(old: old, new: new, myers: solver)
            histogram.solve(old: prefix ..< oldEnd, new: prefix ..< newEnd, into: &edits)
        } else {
            solver.solve(old: prefix ..< oldEnd, new: prefix ..< newEnd, into: &edits)
        }

        for offset in 0 ..< (old.count - oldEnd) {
            edits.append(.equal(old: oldEnd + offset, new: newEnd + offset))
        }
        return edits
    }

    /// Diffs lines through `pipeline`: interned so each comparison in the inner loop is an integer comparison,
    /// then refined by every stage the pipeline wires in.
    public static func diffLines(_ old: [Substring], _ new: [Substring], pipeline: DiffPipeline = DiffPipeline())
        -> [DiffEdit]
    {
        var identifiers: [Substring: Int] = [:]
        identifiers.reserveCapacity(old.count + new.count)

        func intern(_ lines: [Substring]) -> [Int] {
            lines.map { line in
                let key = pipeline.whitespace.normalized(line)
                if let identifier = identifiers[key] { return identifier }
                let identifier = identifiers.count
                identifiers[key] = identifier
                return identifier
            }
        }

        let context = LineDiffContext(
            old: intern(old), new: intern(new), oldIndents: old.map(indent(of:)), newIndents: new.map(indent(of:)))
        var edits = pipeline.lineDiff.diff(context.old, context.new)
        for refiner in pipeline.refiners {
            edits = refiner.refine(edits, lines: context)
        }
        return edits
    }

    /// Leading whitespace width with tabs to the next multiple of eight, or nil for a blank line; git's `get_indent`.
    static func indent(of line: Substring) -> Int? {
        var width = 0
        for byte in line.utf8 {
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
    private var myers: MyersSolver<Element>

    init(old: [Element], new: [Element], myers: MyersSolver<Element>) {
        self.old = old
        self.new = new
        self.myers = myers
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
                    if oldRange.isEmpty {
                        for index in newRange { edits.append(.insert(new: index)) }
                    } else if newRange.isEmpty {
                        for index in oldRange { edits.append(.delete(old: index)) }
                    } else if let anchor = bestAnchor(old: oldRange, new: newRange) {
                        work.append(
                            .ranges(
                                (anchor.oldStart + anchor.length) ..< oldRange.upperBound,
                                (anchor.newStart + anchor.length) ..< newRange.upperBound))
                        work.append(.equal(oldStart: anchor.oldStart, newStart: anchor.newStart, count: anchor.length))
                        work.append(
                            .ranges(oldRange.lowerBound ..< anchor.oldStart, newRange.lowerBound ..< anchor.newStart))
                    } else {
                        myers.solve(old: oldRange, new: newRange, into: &edits)
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

    private let old: [Element]
    private let new: [Element]
    private var forward: [Int]
    private var backward: [Int]
    private let offset: Int

    init(old: [Element], new: [Element]) {
        self.old = old
        self.new = new
        let maximum = (old.count + new.count + 1) / 2 + 1
        offset = maximum + 1
        forward = Array(repeating: 0, count: 2 * maximum + 3)
        backward = forward
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
                    let n = oldRange.count
                    let m = newRange.count
                    if n == 0 {
                        for index in newRange { edits.append(.insert(new: index)) }
                        continue
                    }
                    if m == 0 {
                        for index in oldRange { edits.append(.delete(old: index)) }
                        continue
                    }

                    let snake = middleSnake(old: oldRange, new: newRange)
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

    private mutating func middleSnake(old oldRange: Range<Int>, new newRange: Range<Int>) -> Snake {
        let n = oldRange.count
        let m = newRange.count
        let delta = n - m
        let isOdd = delta & 1 != 0
        let maximum = (n + m + 1) / 2 + 1

        forward[offset + 1] = 0
        backward[offset + 1] = 0

        for d in 0 ... maximum {
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
                        return Snake(x: startX, y: startY, u: x, v: y, edits: 2 * d - 1)
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
                        return Snake(x: n - x, y: m - y, u: n - startX, v: m - startY, edits: 2 * d)
                    }
                }
                k += 2
            }
        }

        preconditionFailure("Myers middle snake search must terminate within (N + M + 1) / 2 + 1 iterations")
    }
}
