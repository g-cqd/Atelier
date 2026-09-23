import AemiTestKit
import Testing

@testable import AtelierFileTree

/// Trees built from paths a patch names, which can be as deep and as odd as its author likes.
struct PathNodeDepthTests {
    @Test
    func `a path deeper than the cap becomes one leaf named by the whole path`() {
        let deep = Array(repeating: "a", count: 30_000).joined(separator: "/") + "/file.swift"
        // On a worker-sized stack, where a walk recursing once per component overflows.
        let walked = runOnConstrainedStack { () -> (ids: [String], files: [String], compacted: [String]) in
            let tree = PathNode.tree(from: [deep, "src/main.swift"])
            let kept = tree.compactMap { $0.filtered { _ in true } }
            return (tree.map(\.id), kept.flatMap(\.filePaths), tree.compacted().map(\.id))
        }
        #expect(walked.ids == ["src", deep])
        #expect(walked.files == ["src/main.swift", deep])
        #expect(walked.compacted == ["src", deep])
    }

    @Test
    func `a path at the cap keeps every directory`() {
        let path = (0 ..< PathNode.maximumDepth).map { "d\($0)" }.joined(separator: "/")
        let deepest = runOnConstrainedStack { () -> (depth: Int, id: String?, files: [String]) in
            let tree = PathNode.tree(from: [path])
            var node = tree.first
            var depth = 1
            while let child = node?.children?.first {
                node = child
                depth += 1
            }
            return (depth, node?.id, tree.compacted().flatMap(\.filePaths))
        }
        #expect(deepest.depth == PathNode.maximumDepth)
        #expect(deepest.id == path)
        #expect(deepest.files == [path])
    }

    @Test
    func `a path that is a file on one side and a directory on the other shows as both`() {
        let tree = PathNode.tree(from: ["Config", "Config/x.swift"])
        #expect(tree.map(\.name) == ["Config", "Config"])
        #expect(tree.map(\.isDirectory) == [true, false])
        #expect(tree.flatMap(\.filePaths) == ["Config/x.swift", "Config"])
        #expect(Set(tree.map(\.id)).count == tree.count)
    }
}
