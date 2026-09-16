import Foundation
import Testing

@testable import KittyFileTree

@Suite(.tags(.navigator))
struct FileTreeNavigatorTests {

    private func makeFileNode(_ name: String, path: String = "/r") -> FileNode {
        FileNode(name: name, path: path + "/\(name)", isDirectory: false)
    }

    private func makeDirNode(
        _ name: String,
        path: String = "/r",
        children: [FileNode] = [],
        isExpanded: Bool = false
    ) -> FileNode {
        FileNode(
            name: name, path: path + "/\(name)", isDirectory: true, children: children,
            isExpanded: isExpanded)
    }

    // MARK: flatten

    @Test func `flatten empty array returns empty result`() {
        let result = FileTreeNavigator.flatten([])
        #expect(result.isEmpty)
    }

    @Test func `flatten assigns depth 0 to top-level nodes`() {
        let nodes = [makeFileNode("a"), makeFileNode("b")]
        let result = FileTreeNavigator.flatten(nodes)

        #expect(result.count == 2)
        #expect(result[0].depth == 0)
        #expect(result[1].depth == 0)
    }

    @Test func `flatten includes children of expanded directory at depth 1`() {
        let child = makeFileNode("child", path: "/r/parent")
        let parent = FileNode(
            name: "parent",
            path: "/r/parent",
            isDirectory: true,
            children: [child],
            isExpanded: true
        )

        let result = FileTreeNavigator.flatten([parent])

        #expect(result.count == 2)
        #expect(result[0].node.name == "parent")
        #expect(result[0].depth == 0)
        #expect(result[1].node.name == "child")
        #expect(result[1].depth == 1)
    }

    @Test func `flatten excludes children of collapsed directory`() {
        let child = makeFileNode("child", path: "/r/parent")
        let parent = FileNode(
            name: "parent",
            path: "/r/parent",
            isDirectory: true,
            children: [child],
            isExpanded: false
        )

        let result = FileTreeNavigator.flatten([parent])

        #expect(result.count == 1)
        #expect(result[0].node.name == "parent")
    }

    @Test func `flatten computes correct depth for nested expansion`() {
        let grandchild = FileNode(name: "gc", path: "/r/p/c/gc", isDirectory: false)
        let child = FileNode(
            name: "c",
            path: "/r/p/c",
            isDirectory: true,
            children: [grandchild],
            isExpanded: true
        )
        let parent = FileNode(
            name: "p",
            path: "/r/p",
            isDirectory: true,
            children: [child],
            isExpanded: true
        )

        let result = FileTreeNavigator.flatten([parent])

        #expect(result.count == 3)
        #expect(result[0].depth == 0)
        #expect(result[1].depth == 1)
        #expect(result[2].depth == 2)
    }

    // MARK: toggleExpand

    @Test func `toggleExpand expands a collapsed directory at root level`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "sub")
        var nodes = DirectoryScanner.scan(tree.root, maxDepth: 0)
        let dirPath = try #require(nodes.first { $0.name == "sub" }).path

        FileTreeNavigator.toggleExpand(in: &nodes, at: dirPath)

        let dir = try #require(nodes.first { $0.name == "sub" })
        #expect(dir.isExpanded == true)
    }

    @Test func `toggleExpand collapses an already-expanded directory`() {
        var nodes: [FileNode] = [
            FileNode(name: "src", path: "/r/src", isDirectory: true, isExpanded: true)
        ]

        FileTreeNavigator.toggleExpand(in: &nodes, at: "/r/src")

        #expect(nodes[0].isExpanded == false)
    }

    @Test func `toggleExpand does nothing when path is not found`() {
        var nodes: [FileNode] = [
            FileNode(name: "src", path: "/r/src", isDirectory: true, isExpanded: false)
        ]

        FileTreeNavigator.toggleExpand(in: &nodes, at: "/r/nonexistent")

        #expect(nodes[0].isExpanded == false)
    }

    @Test func `toggleExpand recurses into nested directories`() {
        let inner = FileNode(
            name: "inner", path: "/r/outer/inner", isDirectory: true, isExpanded: false)
        var nodes: [FileNode] = [
            FileNode(
                name: "outer",
                path: "/r/outer",
                isDirectory: true,
                children: [inner],
                isExpanded: true
            )
        ]

        FileTreeNavigator.toggleExpand(in: &nodes, at: "/r/outer/inner")

        #expect(nodes[0].children[0].isExpanded == true)
    }

    @Test func `toggleExpand lazy-loads children when expanding empty directory`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "populated")
        try tree.createFile(named: "populated/README.md")

        var nodes = DirectoryScanner.scan(tree.root, maxDepth: 0)
        var dir = try #require(nodes.first { $0.name == "populated" })
        #expect(dir.children.isEmpty)

        FileTreeNavigator.toggleExpand(in: &nodes, at: dir.path)

        dir = try #require(nodes.first { $0.name == "populated" })
        #expect(dir.isExpanded == true)
        #expect(!dir.children.isEmpty)
    }
}
