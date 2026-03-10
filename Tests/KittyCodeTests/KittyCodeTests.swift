import Foundation
import Testing
@testable import KittyCode

@Suite("KittyCode Config")
struct KittyCodeConfigTests {
    @Test("ColorRGB parses hex string")
    func colorRGBHexParsing() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test("ColorRGB codable supports hex string")
    func colorRGBCodableHex() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test("ColorRGB rejects invalid hex")
    func colorRGBInvalidHex() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
    }

    @Test("Color scheme uses terminal default backgrounds")
    @MainActor
    func colorSchemeUsesDefaultBackgrounds() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

@Suite("KittyCode Navigation")
@MainActor
struct KittyCodeNavigationTests {
    @Test("Word jump forward moves to next token")
    func jumpForward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("Word jump backward moves to previous token start")
    func jumpBackward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("ensureEditorVisible updates horizontal scroll")
    func ensureHorizontalVisible() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["0123456789abcdefghijklmnopqrstuvwxyz"]
        state.cursorRow = 0
        state.cursorCol = 25
        state.hScrollOffset = 0
        state.config.wrapLines = false

        ensureEditorVisible(state, contentRows: 10, availWidth: 8)
        #expect(state.hScrollOffset > 0)
        #expect(state.hScrollOffset == 18)
    }

    @Test("ensureTreeVisible scrolls selected row into viewport")
    func ensureTreeVisibleScrollsSelection() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.flatTree = (0..<40).map { i in
            (depth: 0, entry: FileEntry(name: "f\(i)", path: "p\(i)", isDirectory: false, children: [], isExpanded: false))
        }
        state.selectedTreeIndex = 25
        state.treeScrollOffset = 0

        ensureTreeVisible(state, contentRows: 10)
        #expect(state.treeScrollOffset == 16)
    }
}