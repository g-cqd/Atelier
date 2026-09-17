import Testing

@testable import AtelierFileTree

struct PathNodeCompactionTests {
    @Test
    func `chains of single child directories fold into one node named by the path`() {
        let tree = PathNode.tree(from: ["x/y/z/one.swift"]).compacted()
        #expect(tree.map(\.name) == ["x/y/z"])
        #expect(tree.map(\.id) == ["x/y/z"])
        #expect(tree.first?.children?.map(\.id) == ["x/y/z/one.swift"])
    }

    @Test
    func `folding stops at a directory with two children`() {
        let tree = PathNode.tree(from: ["a/b/c/file.swift", "a/b/d.swift"]).compacted()
        #expect(tree.map(\.name) == ["a/b"])
        #expect(tree.first?.children?.map(\.name) == ["c", "d.swift"])
        #expect(tree.first?.children?.first?.children?.map(\.id) == ["a/b/c/file.swift"])
    }

    @Test
    func `a directory holding a single file keeps its own node`() {
        let tree = PathNode.tree(from: ["docs/readme.txt", "src/main.swift"]).compacted()
        #expect(tree.map(\.name) == ["docs", "src"])
    }
}

struct FileNodeChainKeyTests {
    @Test
    func `every directory of a single child chain shares the key of the deepest one`() throws {
        let tree = PathNode.tree(from: ["a/b/c/one.swift", "a/b/c/two.swift"])
        let a = try #require(tree.first)
        let b = try #require(a.children?.first)
        let c = try #require(b.children?.first)
        #expect([a, b, c].map(\.chainKey) == ["a/b/c", "a/b/c", "a/b/c"])
    }

    @Test
    func `the compacted row carries the same key as the chain it folds`() throws {
        let hierarchy = PathNode.tree(from: ["a/b/c/one.swift", "a/b/c/two.swift"])
        let compact = hierarchy.compacted()
        #expect(compact.map(\.chainKey) == ["a/b/c"])
        #expect(compact.first?.id == hierarchy.first?.chainKey)
    }

    @Test
    func `a chain stops at a directory with two children`() throws {
        let tree = PathNode.tree(from: ["a/b/c/file.swift", "a/b/d.swift"])
        let a = try #require(tree.first)
        let b = try #require(a.children?.first)
        let c = try #require(b.children?.first)
        #expect(a.chainKey == "a/b")
        #expect(b.chainKey == "a/b")
        #expect(c.chainKey == "a/b/c")
    }

    @Test
    func `a directory holding a single file and a file keep their own ids`() throws {
        let tree = PathNode.tree(from: ["docs/readme.txt"])
        let docs = try #require(tree.first)
        #expect(docs.chainKey == "docs")
        #expect(docs.children?.first?.chainKey == "docs/readme.txt")
    }
}
