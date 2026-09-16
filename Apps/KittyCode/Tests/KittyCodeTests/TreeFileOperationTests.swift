import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct TreeFileOperationTests {
    @Test
    func `tree file create undo redo roundtrips on disk`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        let fileURL = rootURL.appendingPathComponent("created.txt")
        #expect(await state.createTreeFile(at: fileURL.path, suggestedDirectory: rootURL.path))
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        await state.undoFileTreeOperation()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        await state.redoFileTreeOperation()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func `selective invalidation preserves unrelated operations`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        // Create file A, then file B
        let fileA = rootURL.appendingPathComponent("a.txt")
        let fileB = rootURL.appendingPathComponent("b.txt")
        #expect(await state.createTreeFile(at: fileA.path, suggestedDirectory: rootURL.path))
        #expect(await state.createTreeFile(at: fileB.path, suggestedDirectory: rootURL.path))

        // Externally create file C (unrelated path)
        let fileC = rootURL.appendingPathComponent("c.txt")
        FileManager.default.createFile(atPath: fileC.path, contents: Data())

        // Refresh — selective invalidation should keep A and B
        await state.loadInitialTree()

        // Undo B should still work
        #expect(state.fileTreeHistory.hasUndo)
        await state.undoFileTreeOperation()
        #expect(!FileManager.default.fileExists(atPath: fileB.path))
        #expect(state.statusMessage.contains("Create b.txt"))
    }

    @Test
    func `selective invalidation removes overlapping operations`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        // Create file A via the editor
        let fileA = rootURL.appendingPathComponent("overlap.txt")
        #expect(await state.createTreeFile(at: fileA.path, suggestedDirectory: rootURL.path))

        // Externally delete the same file
        try FileManager.default.removeItem(atPath: fileA.path)

        // Refresh — should invalidate the operation since overlap.txt path changed
        await state.loadInitialTree()
        #expect(!state.fileTreeHistory.hasUndo)
    }

    @Test
    func `status message includes operation description`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        let fileURL = rootURL.appendingPathComponent("hello.swift")
        #expect(await state.createTreeFile(at: fileURL.path, suggestedDirectory: rootURL.path))

        await state.undoFileTreeOperation()
        #expect(state.statusMessage == "Undo: Create hello.swift")

        await state.redoFileTreeOperation()
        #expect(state.statusMessage == "Redo: Create hello.swift")
    }

    @Test
    func `partial stack truncation preserves earlier operations`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        // Create A, B, C
        let fileA = rootURL.appendingPathComponent("a.txt")
        let fileB = rootURL.appendingPathComponent("b.txt")
        let fileC = rootURL.appendingPathComponent("c.txt")
        #expect(await state.createTreeFile(at: fileA.path, suggestedDirectory: rootURL.path))
        #expect(await state.createTreeFile(at: fileB.path, suggestedDirectory: rootURL.path))
        #expect(await state.createTreeFile(at: fileC.path, suggestedDirectory: rootURL.path))

        // Externally modify B's path (delete and recreate with different content)
        try FileManager.default.removeItem(atPath: fileB.path)

        // Refresh — B overlaps, so B and C (above B) should be removed, A preserved
        await state.loadInitialTree()

        // Only A's undo should remain
        #expect(state.fileTreeHistory.hasUndo)
        #expect(state.fileTreeHistory.peekUndo?.description == "Create a.txt")

        // Undo A
        await state.undoFileTreeOperation()
        #expect(!FileManager.default.fileExists(atPath: fileA.path))
        #expect(!state.fileTreeHistory.hasUndo)
    }

    @Test
    func `tree history maxOperationSteps prunes oldest entries`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var config = KittyConfig()
        config.editor.maxTreeUndoSteps = 3
        let state = EditorState(rootPath: rootURL.path, config: config)
        await state.loadInitialTree(validateHistory: false)

        for i in 1 ... 5 {
            let file = rootURL.appendingPathComponent("file\(i).txt")
            #expect(await state.createTreeFile(at: file.path, suggestedDirectory: rootURL.path))
        }

        // Should only have 3 undo steps
        var undoCount = 0
        while state.fileTreeHistory.hasUndo {
            await state.undoFileTreeOperation()
            undoCount += 1
        }
        #expect(undoCount == 3)
    }

    @Test
    func `delete of large directory skips history recording`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        var config = KittyConfig()
        config.editor.snapshotMaxFiles = 5
        let state = EditorState(rootPath: rootURL.path, config: config)

        // Create a directory with more files than the threshold
        let bigDir = rootURL.appendingPathComponent("bigdir")
        try FileManager.default.createDirectory(at: bigDir, withIntermediateDirectories: true)
        for i in 0 ..< 10 {
            let file = bigDir.appendingPathComponent("f\(i).txt")
            FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        }

        await state.loadInitialTree(validateHistory: false)

        #expect(await state.deleteTreeItem(at: bigDir.path))
        #expect(!state.fileTreeHistory.hasUndo)
        #expect(state.statusMessage.contains("too large for undo"))
    }

    @Test
    func `delete of small directory records history normally`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())

        let smallDir = rootURL.appendingPathComponent("smalldir")
        try FileManager.default.createDirectory(at: smallDir, withIntermediateDirectories: true)
        for i in 0 ..< 3 {
            let file = smallDir.appendingPathComponent("f\(i).txt")
            FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        }

        await state.loadInitialTree(validateHistory: false)

        #expect(await state.deleteTreeItem(at: smallDir.path))
        #expect(state.fileTreeHistory.hasUndo)
        #expect(!state.statusMessage.contains("too large"))
    }
}
