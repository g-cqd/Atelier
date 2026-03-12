import Foundation
import Testing

@testable import KittyFileTree

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
