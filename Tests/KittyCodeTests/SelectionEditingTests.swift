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
struct SelectionEditingTests {
    private func makeSUT(fileContent: [String] = ["hello world"]) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.bufferManager.open(
            filePath: "/test.txt", fileName: "test.txt",
            content: fileContent.joined(separator: "\n"), language: nil)
        state.restoreStateFromActiveBuffer()
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)),
            columns: 80,
            rows: 24
        )
        return (state, pipeline)
    }

    private func setSelection(
        _ state: EditorState, from: (row: Int, col: Int), to: (row: Int, col: Int)
    ) {
        state.selection = TextSelection(
            anchor: TextPosition(row: from.row, col: from.col),
            head: TextPosition(row: to.row, col: to.col)
        )
    }

    // MARK: shouldReplaceSelectionBeforeHandling (tested via handleEditorKey behaviour)

    @Test
    func `enter key replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)), state: sut.state,
            pipeline: sut.pipeline)

        #expect(sut.state.fileContent == ["", " world"])
        #expect(!sut.state.hasActiveSelection)
    }

    @Test
    func `backspace key replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: Key.backspace.rawValue)), state: sut.state,
            pipeline: sut.pipeline)

        #expect(sut.state.fileContent == [" world"])
        #expect(!sut.state.hasActiveSelection)
    }

    @Test
    func `tab key replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(event: .key(KeyEvent(keyCode: 9)), state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.fileContent == ["\t world"])
        #expect(!sut.state.hasActiveSelection)
    }

    @Test
    func `associated text key replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.x, modifiers: [], associatedText: "X")),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == ["X world"])
        #expect(!sut.state.hasActiveSelection)
    }

    @Test
    func `ctrl combo does not replace active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))
        let contentBefore = sut.state.fileContent

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.b, modifiers: .ctrl)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == contentBefore)
    }

    @Test
    func `function key above 256 does not replace active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))
        let contentBefore = sut.state.fileContent

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: Key.pageDown.rawValue, modifiers: [])),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == contentBefore)
    }

    @Test
    func `printable character replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(
            // swiftlint:disable:next force_unwrapping
            event: .key(KeyEvent(keyCode: UInt32(Character("a").asciiValue!), modifiers: [])),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == ["a world"])
        #expect(!sut.state.hasActiveSelection)
    }

    @Test
    func `unicode scalar fallback replaces active selection`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: 0x1F600)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == ["😀 world"])
        #expect(!sut.state.hasActiveSelection)
    }

    // MARK: Read-only mode

    @Test
    func `textDidChange with readOnly true sets status message and does not modify buffer`() {
        let sut = makeSUT(fileContent: ["original"])
        sut.state.readOnly = true
        let contentBefore = sut.state.fileContent

        sut.state.textDidChange()

        #expect(sut.state.statusMessage == "Read-only mode")
        #expect(sut.state.fileContent == contentBefore)
    }

    @Test
    func
        `textDidChange mutation with readOnly true sets status message and does not modify buffer`()
    {
        let sut = makeSUT(fileContent: ["original"])
        sut.state.readOnly = true
        let contentBefore = sut.state.fileContent

        // Build a dummy mutation via a throwaway operation on a local copy
        var tmpBuffer = sut.state.textBuffer
        var tmpCursor = sut.state.textCursor
        let mutation = TextOperations.insert("x", into: &tmpBuffer, at: &tmpCursor)

        sut.state.textDidChange(mutation)

        #expect(sut.state.statusMessage == "Read-only mode")
        #expect(sut.state.fileContent == contentBefore)
    }

    @Test
    func `typing into readOnly editor does not mutate content`() {
        let sut = makeSUT(fileContent: ["original"])
        sut.state.readOnly = true
        let contentBefore = sut.state.fileContent

        _ = handleEvent(
            // swiftlint:disable:next force_unwrapping
            event: .key(KeyEvent(keyCode: UInt32(Character("z").asciiValue!), modifiers: [])),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == contentBefore)
    }

    // MARK: Paste-over-selection undo roundtrip

    @Test
    func `paste over selection can be undone back to pre-paste state`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 0), to: (0, 5))

        _ = handleEvent(event: .paste("REPLACED"), state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.fileContent == ["REPLACED world"])

        sut.state.undoActiveBuffer()
        sut.state.undoActiveBuffer()

        #expect(sut.state.fileContent == ["hello world"])
    }

    // MARK: Cut undo roundtrip

    @Test
    func `cut records undo history so undoing restores the text`() {
        let sut = makeSUT(fileContent: ["hello world"])
        setSelection(sut.state, from: (0, 6), to: (0, 11))
        var writes: [[UInt8]] = []
        sut.state.terminalWriter = { writes.append($0) }

        _ = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.x, modifiers: .super)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.fileContent == ["hello "])

        sut.state.undoActiveBuffer()

        #expect(sut.state.fileContent == ["hello world"])
    }
}
