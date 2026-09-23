import AemiRuntime
import Foundation
import Testing

@testable import AtelierFileTree

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
        for i in 1 ... 10 {
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

    // MARK: Symlink containment

    /// A symlink to a sibling whose name extends the root's (`/tmp/root` → `/tmp/root-evil`) lies outside the root:
    /// containment is checked by path component, not by prefix.
    @Test func `scan rejects symlink whose target shares a prefix with sibling under root`()
        throws
    {
        let tree = try TempTree()
        // Create a sibling-of-root whose name begins with `tree.root` prefix.
        let siblingPath = tree.root + "-evil-sibling"
        try FileManager.default.createDirectory(
            atPath: siblingPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: siblingPath) }
        try "x"
            .write(
                toFile: siblingPath + "/secret.txt", atomically: true, encoding: .utf8)

        // Place a symlink inside the workspace pointing at the sibling.
        let linkPath = tree.root + "/link"
        try FileManager.default.createSymbolicLink(
            atPath: linkPath, withDestinationPath: siblingPath)

        let entries = DirectoryScanner.scan(
            tree.root, maxDepth: 2, withinRoot: tree.root)
        let names = entries.map(\.name)
        #expect(!names.contains("link"), "symlink escaping the workspace must not appear")
    }

    /// A symlink several levels deep that points outside the workspace is checked against the workspace root, not
    /// against its parent directory.
    @Test func `scanAsync rejects deep symlink that escapes workspace`() async throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "level1")
        try tree.createDirectory(named: "level1/level2")

        // Sibling-of-workspace acting as the escape target.
        let escapeTarget = tree.root + "-escape-target"
        try FileManager.default.createDirectory(
            atPath: escapeTarget, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: escapeTarget) }
        try "x"
            .write(
                toFile: escapeTarget + "/leaked.txt", atomically: true, encoding: .utf8)

        let deepLink = tree.root + "/level1/level2/escape"
        try FileManager.default.createSymbolicLink(
            atPath: deepLink, withDestinationPath: escapeTarget)

        let pool = BlockingOffloadPool(width: 1)
        defer { pool.shutdown() }
        let entries = try await DirectoryScanner.scanAsync(tree.root, maxDepth: 5, withinRoot: tree.root, pool: pool)

        // Walk to level1/level2 children and assert no `escape` link survived.
        let level1 = try #require(entries.first { $0.name == "level1" })
        let level2 = try #require(level1.children.first { $0.name == "level2" })
        let escapeNames = level2.children.map(\.name)
        #expect(
            !escapeNames.contains("escape"),
            "deep symlink escaping the workspace must not appear at any depth")
    }

    /// A symlink into another part of the workspace is kept, even from a nested directory it does not point into.
    @Test func `scan accepts symlink whose target stays inside the workspace`() throws {
        let tree = try TempTree()
        try tree.createDirectory(named: "siblingA")
        try tree.createFile(named: "siblingA/note.txt", content: "hi")
        try tree.createDirectory(named: "siblingB")

        // Link inside siblingB pointing at a file under siblingA. Both live
        // under the workspace, so containment holds at workspace-root level
        // but does NOT hold against the immediate parent (siblingB).
        let linkPath = tree.root + "/siblingB/peek"
        let targetPath = tree.root + "/siblingA/note.txt"
        try FileManager.default.createSymbolicLink(
            atPath: linkPath, withDestinationPath: targetPath)

        let entries = DirectoryScanner.scan(
            tree.root, maxDepth: 3, withinRoot: tree.root)

        let siblingB = try #require(entries.first { $0.name == "siblingB" })
        let names = siblingB.children.map(\.name)
        #expect(
            names.contains("peek"),
            "intra-workspace symlink must be visible when withinRoot is the workspace")
    }
}
