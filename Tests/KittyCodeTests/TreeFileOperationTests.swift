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

@testable import KittyCode

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
    func `tree history invalidates on refreshed divergence`() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        await state.loadInitialTree(validateHistory: false)

        let createdURL = rootURL.appendingPathComponent("created.txt")
        #expect(await state.createTreeFile(at: createdURL.path, suggestedDirectory: rootURL.path))

        let externalURL = rootURL.appendingPathComponent("external.txt")
        guard FileManager.default.createFile(atPath: externalURL.path, contents: Data()) else {
            Issue.record("Failed to create external file")
            return
        }

        await state.loadInitialTree()
        #expect(state.statusMessage == "File history cleared after tree refresh")

        await state.undoFileTreeOperation()
        #expect(state.statusMessage == "Nothing to undo")
    }
}
