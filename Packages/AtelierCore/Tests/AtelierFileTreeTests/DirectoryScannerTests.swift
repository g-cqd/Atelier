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

    // MARK: Symlink containment (NF4 regression)

    /// Regression: `isWithinRoot` used to do `hasPrefix` on resolved paths,
    /// so a symlink to a sibling whose name shared a prefix with the parent
    /// (e.g. workspace `/tmp/root` → symlink target `/tmp/root-evil`) would
    /// be accepted. Now SecurePath.isValid does component-by-component
    /// containment so the prefix-only match no longer passes.
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

    /// Regression: recursion used to pass the immediate parent directory as
    /// `root`, so a symlink several levels deep pointing outside the
    /// workspace was checked against the wrong root and incorrectly passed.
    /// With workspace-root threading via `withinRoot:`, the check root stays
    /// at the workspace level at every depth.
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

        let entries = await DirectoryScanner.scanAsync(
            tree.root, maxDepth: 5, withinRoot: tree.root)

        // Walk to level1/level2 children and assert no `escape` link survived.
        let level1 = try #require(entries.first { $0.name == "level1" })
        let level2 = try #require(level1.children.first { $0.name == "level2" })
        let escapeNames = level2.children.map(\.name)
        #expect(
            !escapeNames.contains("escape"),
            "deep symlink escaping the workspace must not appear at any depth")
    }

    /// Sanity: a symlink that resolves to a path inside the workspace is
    /// still allowed (the defence rejects only escapes, not internal
    /// references). Without workspace-root threading, this would be
    /// incorrectly rejected when the link sits inside a nested subdirectory.
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
