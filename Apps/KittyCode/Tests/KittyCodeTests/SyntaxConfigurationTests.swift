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
struct SyntaxConfigurationTests {
    @Test
    func `syntaxHighlighting=false produces plain spans`() {
        var config = KittyConfig()
        config.syntax.enabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["func hello() {", "}"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "func hello() {")
    }

    @Test
    func `disabled language produces plain spans`() {
        var config = KittyConfig()
        config.syntax.disabledLanguages = ["swift"]
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["let x = 42"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 1)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "let x = 42")
    }
}
