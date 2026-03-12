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
struct EditorSnapshotInvalidationTests {

    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        makeKittyCodeNavigationContext(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `insertText invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 5

        insertText("!", into: sut.state)

        #expect(sut.state.fileContent == ["hello!"])
        #expect(sut.state.fileLineCount == 1)
    }

    @Test
    func `handleEvent enter invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 2

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["he", "llo"])
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func `handleEvent backspace invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["he", "llo"])
        _ = sut.state.fileContent
        sut.state.cursorRow = 1
        sut.state.cursorCol = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.backspace.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["hello"])
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 2)
    }
}
