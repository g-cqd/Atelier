import Foundation
import Testing

@testable import KittyFileTree

// MARK: - Tags

extension Tag {
    @Tag static var fileNode: Self
    @Tag static var scanner: Self
    @Tag static var navigator: Self
    @Tag static var securePath: Self
}

// MARK: - FileNode Tests

@Suite(.tags(.fileNode))
struct FileNodeTests {

    // MARK: Initialisation

    @Test func `init stores all provided values`() {
        let child = FileNode(name: "child.txt", path: "/root/child.txt", isDirectory: false)
        let node = FileNode(
            name: "src",
            path: "/root/src",
            isDirectory: true,
            children: [child],
            isExpanded: true
        )

        #expect(node.name == "src")
        #expect(node.path == "/root/src")
        #expect(node.isDirectory == true)
        #expect(node.children.count == 1)
        #expect(node.children[0].name == "child.txt")
        #expect(node.isExpanded == true)
    }

    @Test func `init defaults children to empty and isExpanded to false`() {
        let node = FileNode(name: "file.swift", path: "/root/file.swift", isDirectory: false)

        #expect(node.children.isEmpty)
        #expect(node.isExpanded == false)
    }

    // MARK: Icon — file

    @Test func `icon for regular file returns three spaces`() {
        let node = FileNode(name: "main.swift", path: "/root/main.swift", isDirectory: false)
        #expect(node.icon == "   ")
    }

    @Test func `icon for collapsed directory returns [+]`() {
        let node = FileNode(
            name: "Sources", path: "/root/Sources", isDirectory: true, isExpanded: false)
        #expect(node.icon == "[+]")
    }

    @Test func `icon for expanded directory returns [-]`() {
        let node = FileNode(
            name: "Sources", path: "/root/Sources", isDirectory: true, isExpanded: true)
        #expect(node.icon == "[-]")
    }

    @Test func `icon toggling reflects isExpanded mutation`() {
        var node = FileNode(name: "lib", path: "/root/lib", isDirectory: true, isExpanded: false)
        #expect(node.icon == "[+]")

        node.isExpanded = true
        #expect(node.icon == "[-]")

        node.isExpanded = false
        #expect(node.icon == "[+]")
    }
}

// MARK: - Temporary Directory Fixture

/// Creates a temporary directory subtree for scanner tests and removes it on deinit.
private final class TempTree: Sendable {
    let root: String

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KittyFileTreeTests-\(Int.random(in: 100_000 ... 999_999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = tmp.path
    }

    /// Creates a file relative to `root` with the given name and optional content.
    func createFile(named name: String, content: String = "") throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Creates a subdirectory relative to `root`.
    func createDirectory(named name: String) throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }
}

// MARK: - DirectoryScanner Tests

@Suite(.tags(.scanner))
struct DirectoryScannerTests {

    // MARK: Basic scanning

    @Test func `scan returns entries for each visible file in directory`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "alpha.swift")
        try tree.createFile(named: "beta.swift")

        let entries = DirectoryScanner.scan(tree.root)

        let names = entries.map(\.name).sorted()
        #expect(names == ["alpha.swift", "beta.swift"])
    }

    @Test func `scan returns empty array for empty directory`() throws {
        let tree = try TempTree()

        let entries = DirectoryScanner.scan(tree.root)

        #expect(entries.isEmpty)
    }

    @Test func `scan returns empty array for nonexistent path`() {
        let entries = DirectoryScanner.scan("/nonexistent/path/\(UUID().uuidString)")
        #expect(entries.isEmpty)
    }

    // MARK: Dotfile exclusion

    @Test func `scan skips dotfiles`() throws {
        let tree = try TempTree()
        try tree.createFile(named: ".hidden")
        try tree.createFile(named: ".gitignore")
        try tree.createFile(named: "visible.txt")

        let entries = DirectoryScanner.scan(tree.root)

        let names = entries.map(\.name)
        #expect(!names.contains(".hidden"))
        #expect(!names.contains(".gitignore"))
        #expect(names.contains("visible.txt"))
    }

    @Test func `scan skips dot-prefixed directories`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: ".build")
        try tree.createFile(named: "Package.swift")

        let entries = DirectoryScanner.scan(tree.root)

        let names = entries.map(\.name)
        #expect(!names.contains(".build"))
        #expect(names.contains("Package.swift"))
    }

    // MARK: maxEntries limit

    @Test func `scan respects maxEntries limit`() throws {
        let tree = try TempTree()
        for i in 1...10 {
            try tree.createFile(named: "file\(i).txt")
        }

        let entries = DirectoryScanner.scan(tree.root, maxEntries: 3)

        #expect(entries.count <= 3)
    }

    @Test func `scan with maxEntries zero returns empty result`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "anything.txt")

        let entries = DirectoryScanner.scan(tree.root, maxEntries: 0)

        #expect(entries.isEmpty)
    }

    // MARK: Sorting

    @Test func `scan places directories before files`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "aaa.txt")
        try tree.createDirectory(named: "zzz")

        let entries = DirectoryScanner.scan(tree.root)

        #expect(entries.first?.isDirectory == true)
        #expect(entries.last?.isDirectory == false)
    }

    @Test func `scan sorts entries case-insensitively within each group`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "Beta.txt")
        try tree.createFile(named: "alpha.txt")
        try tree.createFile(named: "Gamma.txt")

        let entries = DirectoryScanner.scan(tree.root)
        let names = entries.map(\.name)

        #expect(names == ["alpha.txt", "Beta.txt", "Gamma.txt"])
    }

    // MARK: Depth control

    @Test func `scan with maxDepth 0 does not recurse into subdirectories`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "sub")
        try tree.createFile(named: "sub/nested.txt")

        let entries = DirectoryScanner.scan(tree.root, maxDepth: 0)

        let dirEntry = try #require(entries.first { $0.name == "sub" })
        #expect(dirEntry.children.isEmpty)
    }

    @Test func `scan with maxDepth 1 populates one level of children`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "sub")
        try tree.createFile(named: "sub/nested.txt")

        let entries = DirectoryScanner.scan(tree.root, maxDepth: 1)

        let dirEntry = try #require(entries.first { $0.name == "sub" })
        #expect(!dirEntry.children.isEmpty)
        #expect(dirEntry.children[0].name == "nested.txt")
    }

    // MARK: Metadata

    @Test func `scan sets isDirectory correctly for directories`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "mydir")

        let entries = DirectoryScanner.scan(tree.root)
        let dir = try #require(entries.first { $0.name == "mydir" })

        #expect(dir.isDirectory == true)
    }

    @Test func `scan sets isDirectory correctly for files`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "myfile.txt")

        let entries = DirectoryScanner.scan(tree.root)
        let file = try #require(entries.first { $0.name == "myfile.txt" })

        #expect(file.isDirectory == false)
    }

    @Test func `scan sets path to absolute full path`() throws {
        let tree = try TempTree()
        try tree.createFile(named: "check.swift")

        let entries = DirectoryScanner.scan(tree.root)
        let file = try #require(entries.first { $0.name == "check.swift" })

        #expect(file.path == "\(tree.root)/check.swift")
    }
}

// MARK: - FileTreeNavigator Tests

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

// MARK: - SecurePath Tests

@Suite(.tags(.securePath))
struct SecurePathTests {

    // MARK: validate — passes

    @Test func `validate does not throw for path equal to root`() throws {
        try SecurePath.validate("/tmp/root", root: "/tmp/root")
    }

    @Test func `validate does not throw for path inside root`() throws {
        try SecurePath.validate("/tmp/root/sub/file.txt", root: "/tmp/root")
    }

    // MARK: validate — throws

    @Test func `validate throws outsideRoot for path traversal using double dot`() {
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/tmp/root/../other", root: "/tmp/root")
        }
    }

    @Test func `validate throws outsideRoot for path entirely outside root`() {
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/etc/passwd", root: "/tmp/root")
        }
    }

    @Test func `validate throws outsideRoot for sibling directory with shared prefix`() {
        // "/tmp/root-evil" must NOT be treated as inside "/tmp/root"
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/tmp/root-evil/file.txt", root: "/tmp/root")
        }
    }

    // MARK: isValid

    @Test func `isValid returns true for path inside root`() {
        #expect(SecurePath.isValid("/tmp/root/a/b", root: "/tmp/root"))
    }

    @Test func `isValid returns false for path outside root`() {
        #expect(!SecurePath.isValid("/etc/hosts", root: "/tmp/root"))
    }

    @Test func `isValid returns false for sibling directory with shared prefix`() {
        #expect(!SecurePath.isValid("/tmp/root-evil", root: "/tmp/root"))
    }

    @Test func `isValid returns true for path equal to root`() {
        #expect(SecurePath.isValid("/tmp/root", root: "/tmp/root"))
    }
}
