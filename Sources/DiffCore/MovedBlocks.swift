/// Blocks of lines that were removed in one place and added unchanged in another; git's `--color-moved` idea.
/// Only runs of at least `minimumLines` count, since single moved lines are mostly coincidence.
public enum MovedBlocks {
    public static let minimumLines = 3

    /// Old and new line indices that belong to a moved block, given the removed and added line ids of a diff.
    /// - Complexity: O(removed runs × added runs × block length)
    public static func detect(removed: [(index: Int, id: Int)], added: [(index: Int, id: Int)]) -> (old: Set<Int>, new: Set<Int>) {
        let removedRuns = runs(of: removed)
        let addedRuns = runs(of: added)
        var movedOld: Set<Int> = []
        var movedNew: Set<Int> = []
        guard !removedRuns.isEmpty, !addedRuns.isEmpty else { return (movedOld, movedNew) }
        var positions: [Int: [(run: Int, offset: Int)]] = [:]
        for (runIndex, run) in removedRuns.enumerated() {
            for (offset, line) in run.enumerated() { positions[line.id, default: []].append((runIndex, offset)) }
        }
        for run in addedRuns {
            var start = 0
            while start < run.count {
                var bestLength = 0
                var bestMatch: (run: Int, offset: Int)?
                for candidate in positions[run[start].id] ?? [] {
                    let source = removedRuns[candidate.run]
                    var length = 0
                    while start + length < run.count, candidate.offset + length < source.count,
                          run[start + length].id == source[candidate.offset + length].id {
                        length += 1
                    }
                    if length > bestLength {
                        bestLength = length
                        bestMatch = candidate
                    }
                }
                if let bestMatch, bestLength >= minimumLines {
                    let source = removedRuns[bestMatch.run]
                    for offset in 0..<bestLength {
                        movedOld.insert(source[bestMatch.offset + offset].index)
                        movedNew.insert(run[start + offset].index)
                    }
                    start += bestLength
                } else {
                    start += 1
                }
            }
        }
        return (movedOld, movedNew)
    }

    /// Consecutive lines grouped into runs.
    private static func runs(of lines: [(index: Int, id: Int)]) -> [[(index: Int, id: Int)]] {
        var runs: [[(index: Int, id: Int)]] = []
        for line in lines {
            if let last = runs.last?.last, last.index + 1 == line.index {
                runs[runs.count - 1].append(line)
            } else {
                runs.append([line])
            }
        }
        return runs
    }
}
