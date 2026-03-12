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
struct PreviewModeTests {
    @Test
    func `openPreview creates a preview buffer`() {
        let manager = BufferManager()
        let idx = manager.openPreview(
            filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `openPreview replaces existing preview buffer`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.txt")
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `pinBuffer removes preview status`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.pinBuffer(at: 0)
        #expect(manager.activeBuffer?.isPreview == false)
        // Opening another preview should NOT replace the pinned buffer
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 2)
    }

    @Test
    func `editing auto-pins preview buffer`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.persistence = .preview
        let state = EditorState(rootPath: ".", config: config)
        state.bufferManager.openPreview(
            filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isPreview == true)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isPreview == false)
    }

    @Test
    func `preview index returns nil when no preview buffers exist`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(manager.previewIndex == nil)
    }
}
