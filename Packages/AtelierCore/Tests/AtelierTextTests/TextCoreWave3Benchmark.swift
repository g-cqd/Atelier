import Foundation
import Testing

@testable import AtelierText

/// Environment-gated before/after measurements on the same inputs; run in a release build.
@Suite struct TextCoreWave3Benchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `undo width pass on one million lines benchmark`() {
        let buffer = TextBuffer(String(repeating: "abc\tdef\n", count: 1_000_000))
        compare(
            "undo width 1M lines",
            before: {
                var width = 0
                for index in 0 ..< buffer.lineCount {
                    width = max(width, TextDisplayMetrics.displayWidth(of: buffer.line(at: index)))
                }
                return width
            },
            after: { TextDocument.computeMaxLineWidth(in: buffer) })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `whole document deletion benchmark`() {
        let data = Data(repeating: UInt8(ascii: "a"), count: 8_000_000)
        let rope = Rope(bytes: data)
        let oldRoot = legacyBuild(data)
        compare(
            "whole delete 8 MB", before: { legacyFullRemove(oldRoot).byteCount },
            after: {
                var copy = rope
                copy.remove(0 ..< copy.byteCount)
                return copy.byteCount
            })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `rope build newline width and append timings`() {
        let data = Data(repeating: UInt8(ascii: "a"), count: 3_400_000)
        let lines = (0 ..< 100_000).map { "let value\($0 % 10) = 42\t// text" }
        compare(
            "newline count 3.4 MB", before: { data.count(where: { $0 == 0x0A }) },
            after: { Rope.countNewlines(in: data) })
        compare(
            "display width 100k",
            before: {
                lines.reduce(0) { width, line in
                    var column = 0
                    for character in line {
                        column += character == "\t" ? 4 - column % 4 : UnicodeWidth.displayWidth(of: character)
                    }
                    return width + column
                }
            }, after: { lines.reduce(0) { $0 + TextDisplayMetrics.displayWidth(of: $1) } })
        compare(
            "rope build 3.4 MB", before: { legacyBuild(data).nodeHash },
            after: { Rope(bytes: data).contentHash })

        var rope = Rope()
        for count in [1_000, 10_000, 50_000, 200_000] {
            while rope.byteCount < count * 6 {
                rope.insert("abcde\n", atByteOffset: rope.byteCount)
            }
            var retained = ContiguousArray<RopeNode>()
            var legacy = legacySpine(after: count, retained: &retained)
            var legacyPath = ContiguousArray<RopeNode>()
            legacyPath.reserveCapacity(retained.count + 101)
            var oldSamples: [Double] = []
            var newSamples: [Double] = []
            for round in 0 ..< 101 {
                let labels = round.isMultiple(of: 2) ? ["before", "after"] : ["after", "before"]
                for label in labels {
                    let start = ContinuousClock.now
                    if label == "before" {
                        legacy = legacyInsert(
                            "abcde\n", into: legacy, path: &legacyPath, retained: &retained)
                        oldSamples.append(milliseconds(start.duration(to: .now)) * 1_000)
                    } else {
                        rope.insert("abcde\n", atByteOffset: rope.byteCount)
                        newSamples.append(milliseconds(start.duration(to: .now)) * 1_000)
                    }
                }
            }
            print("W3 append after \(count): before \(oldSamples.sorted()[50]) µs after \(newSamples.sorted()[50]) µs")
            legacy = RopeNode.makeLeaf(Data())
            while retained.popLast() != nil {}
        }
    }

    private func compare(_ name: String, before: @escaping () -> Int, after: @escaping () -> Int) {
        var oldSamples: [Double] = []
        var newSamples: [Double] = []
        var sink = 0
        for round in 0 ..< 9 {
            let operations: [(String, () -> Int)] = [("before", before), ("after", after)]
            for (label, operation) in round.isMultiple(of: 2) ? operations : operations.reversed() {
                let start = ContinuousClock.now
                sink &+= operation()
                let elapsed = milliseconds(start.duration(to: .now))
                if label == "before" { oldSamples.append(elapsed) } else { newSamples.append(elapsed) }
            }
        }
        print("W3 \(name): before \(oldSamples.sorted()[4]) ms after \(newSamples.sorted()[4]) ms, sink \(sink)")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private func legacyBuild(_ data: Data) -> RopeNode {
        if data.count <= Rope.maxLeafSize {
            return .leaf(LeafNode(data: data, newlineCount: data.count(where: { $0 == 0x0A })))
        }
        let middle = data.count / 2
        return RopeNode.makeBranch(
            legacyBuild(data.subdata(in: 0 ..< middle)),
            legacyBuild(data.subdata(in: middle ..< data.count)))
    }

    private func legacyFullRemove(_ node: RopeNode) -> RopeNode {
        switch node {
            case .leaf:
                return RopeNode.makeLeaf(Data())
            case .branch(let branch):
                return RopeNode.mergeOrBranch(legacyFullRemove(branch.left), legacyFullRemove(branch.right))
        }
    }

    /// Constructs the exact leaf-size shape after repeated old-style appends, without retaining their old roots.
    private func legacySpine(after appends: Int, retained: inout ContiguousArray<RopeNode>) -> RopeNode {
        var rightSize = 0
        var leftSizes: [Int] = []
        for _ in 0 ..< appends {
            rightSize += 6
            if rightSize > Rope.maxLeafSize {
                let leftSize = rightSize / 2
                leftSizes.append(leftSize)
                rightSize -= leftSize
            }
        }
        retained.reserveCapacity((leftSizes.count + 1) * 105)
        var root = RopeNode.makeLeaf(Data(repeating: UInt8(ascii: "a"), count: rightSize))
        for size in leftSizes.reversed() {
            root = RopeNode.makeBranch(
                RopeNode.makeLeaf(Data(repeating: UInt8(ascii: "a"), count: size)), root)
            retained.append(root)
        }
        return root
    }

    /// The previous right-spine rebuild, with an explicit path and retained nodes to avoid stack exhaustion in ARC.
    private func legacyInsert(
        _ string: String, into node: RopeNode, path: inout ContiguousArray<RopeNode>,
        retained: inout ContiguousArray<RopeNode>
    ) -> RopeNode {
        path.removeAll(keepingCapacity: true)
        var cursor = node
        while case .branch(let branch) = cursor {
            path.append(branch.left)
            cursor = branch.right
        }
        guard case .leaf(let leaf) = cursor else { preconditionFailure("The right spine ends in a leaf") }
        var data = leaf.data
        data.append(contentsOf: string.utf8)
        var result = RopeNode.fromLeafData(data)
        if case .branch = result { retained.append(result) }
        while let left = path.popLast() {
            result = RopeNode.makeBranch(left, result)
            retained.append(result)
        }
        return result
    }
}
