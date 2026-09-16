/// Adjusts the token-level edit script of a line pair without changing what it reconstructs.
public protocol IntralineRefining: Sendable {
    /// - Parameters:
    ///   - edits: The token-level edit script to adjust.
    ///   - oldRanges: Unit ranges of the old line's tokens, the edit script's deletions index into them.
    ///   - newRanges: Unit ranges of the new line's tokens, the edit script's insertions index into them.
    /// - Returns: An edit script over the same tokens that reconstructs the same lines.
    func refine(_ edits: [DiffEdit], oldRanges: [Range<Int>], newRanges: [Range<Int>]) -> [DiffEdit]
}

/// diff-match-patch's semantic cleanup: an equality short enough to be coincidence between two changes is folded
/// into them, so `foo` to `bar` reads as one replacement rather than as scattered common letters.
public struct SemanticCleanup: IntralineRefining {
    public init() {}

    public func refine(_ edits: [DiffEdit], oldRanges: [Range<Int>], newRanges: [Range<Int>]) -> [DiffEdit] {
        var runs = Run.runs(of: edits, oldRanges: oldRanges, newRanges: newRanges)
        var changed = true
        while changed {
            changed = false
            var index = 0
            while index < runs.count {
                let run = runs[index]
                guard run.isEqual, index > 0, index < runs.count - 1 else {
                    index += 1
                    continue
                }
                let before = Run.changeLength(of: runs, endingAt: index)
                let after = Run.changeLength(of: runs, startingAt: index + 1)
                if run.units <= max(before.deleted, before.inserted), run.units <= max(after.deleted, after.inserted) {
                    runs[index] = Run(
                        edits: run.edits.flatMap { edit -> [DiffEdit] in
                            guard case .equal(let old, let new) = edit else { return [edit] }
                            return [.delete(old: old), .insert(new: new)]
                        }, deleted: run.deleted, inserted: run.inserted, isEqual: false)
                    changed = true
                }
                index += 1
            }
            if changed { runs = Run.merged(runs) }
        }
        return runs.flatMap(\.edits).sorted(by: Self.scriptOrder)
    }

    /// Deletions before insertions within one change, both in index order; equalities keep their place.
    private static func scriptOrder(_ lhs: DiffEdit, _ rhs: DiffEdit) -> Bool {
        position(of: lhs) < position(of: rhs)
    }

    private static func position(of edit: DiffEdit) -> (Int, Int, Int) {
        switch edit {
            case .equal(let old, let new): (old + new, 0, 0)
            case .delete(let old): (old * 2, 1, old)
            case .insert(let new): (new * 2, 2, new)
        }
    }

    private struct Run {
        var edits: [DiffEdit]
        /// Units on the old side and on the new side; equal for an equality.
        var deleted: Int
        var inserted: Int
        var isEqual: Bool

        var units: Int { max(deleted, inserted) }
        var changeLength: (deleted: Int, inserted: Int) { (deleted, inserted) }

        static func runs(of edits: [DiffEdit], oldRanges: [Range<Int>], newRanges: [Range<Int>]) -> [Run] {
            var runs: [Run] = []
            for edit in edits {
                let run: Run
                switch edit {
                    case .equal(let old, _):
                        run = Run(
                            edits: [edit], deleted: oldRanges[old].count, inserted: oldRanges[old].count, isEqual: true)
                    case .delete(let old):
                        run = Run(edits: [edit], deleted: oldRanges[old].count, inserted: 0, isEqual: false)
                    case .insert(let new):
                        run = Run(edits: [edit], deleted: 0, inserted: newRanges[new].count, isEqual: false)
                }
                if let last = runs.last, last.isEqual == run.isEqual {
                    runs[runs.count - 1].edits += run.edits
                    runs[runs.count - 1].deleted += run.deleted
                    runs[runs.count - 1].inserted += run.inserted
                } else {
                    runs.append(run)
                }
            }
            return runs
        }

        static func merged(_ runs: [Run]) -> [Run] {
            var merged: [Run] = []
            for run in runs {
                if let last = merged.last, last.isEqual == run.isEqual {
                    merged[merged.count - 1].edits += run.edits
                    merged[merged.count - 1].deleted += run.deleted
                    merged[merged.count - 1].inserted += run.inserted
                } else {
                    merged.append(run)
                }
            }
            return merged
        }

        static func changeLength(of runs: [Run], endingAt index: Int) -> (deleted: Int, inserted: Int) {
            index > 0 ? runs[index - 1].changeLength : (0, 0)
        }

        static func changeLength(of runs: [Run], startingAt index: Int) -> (deleted: Int, inserted: Int) {
            index < runs.count ? runs[index].changeLength : (0, 0)
        }
    }
}
