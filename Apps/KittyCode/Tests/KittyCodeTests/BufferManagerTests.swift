import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct BufferManagerTests {
    @Test
    func `open creates a new buffer`() {
        let manager = BufferManager()
        let idx = manager.open(
            filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeIndex == 0)
        #expect(manager.activeBuffer?.fileName == "a.swift")
    }

    @Test
    func `open same file twice returns existing index`() {
        let manager = BufferManager()
        let idx1 = manager.open(
            filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        let idx2 = manager.open(
            filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx1 == idx2)
        #expect(manager.count == 1)
    }

    @Test
    func `open two different files yields count 2`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        #expect(manager.count == 2)
        #expect(manager.activeIndex == 1)
    }

    @Test
    func `nextTab and prevTab cycle through buffers`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        manager.open(filePath: "/c.swift", fileName: "c.swift", content: "c", language: "swift")
        #expect(manager.activeIndex == 2)

        manager.nextTab()
        #expect(manager.activeIndex == 0)

        manager.prevTab()
        #expect(manager.activeIndex == 2)
    }

    @Test
    func `close dirty buffer returns promptSave`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        let result = manager.close(at: 0)
        #expect(result == .promptSave)
        #expect(manager.count == 1)
    }

    @Test
    func `close clean buffer removes it`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")

        let result = manager.close(at: 0)
        #expect(result == .closed)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.swift")
    }

    @Test
    func `forceClose removes dirty buffer`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        manager.forceClose(at: 0)
        #expect(manager.count == 0)
        #expect(manager.isEmpty)
    }
}
