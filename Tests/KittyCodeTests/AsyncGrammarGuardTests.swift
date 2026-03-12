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
struct AsyncGrammarGuardTests {
    @Test
    func `scroll position unchanged after refreshHighlights`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = (0..<50).map { "line \($0)" }
        state.scrollOffset = 20
        state.hScrollOffset = 5
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.scrollOffset == 20)
        #expect(state.hScrollOffset == 5)
    }

    @Test
    func `isLoadingGrammar defaults to false`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.isLoadingGrammar == false)
    }
}
