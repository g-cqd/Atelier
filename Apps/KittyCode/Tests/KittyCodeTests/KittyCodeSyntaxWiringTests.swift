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
struct KittyCodeSyntaxWiringTests {
    @Test
    func `language highlighter returns styled json output when bundled resources are available`()
        async
    {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json")
        let lines = session.highlightDocument(source: "true")
        #expect(available)
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "true")
        #expect(lines[0][0].style != Theme.monokai.defaultStyle)
    }

    @Test func `swift grammar resources are bundled for kittycode`() {
        #expect(LanguageHighlighter.hasBundledResources(for: "swift"))
    }

    @Test func `language highlighter falls back for unsupported languages`() {
        let lines = LanguageHighlighter.highlightDocument(
            source: "// comment", language: "unknown_lang")
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "// comment")
    }

    @Test
    @MainActor
    func `EditorState refreshHighlights populates per-line styled output`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["true", "42"]
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(!state.highlightedLine(at: 0).isEmpty)
        #expect(!state.highlightedLine(at: 1).isEmpty)
    }

    @Test
    @MainActor
    func `EditorState fallback highlighting reuses line-based input for unsupported languages`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["// comment", "value"]
        state.currentLanguage = "unknown_lang"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "// comment")
        #expect(state.highlightedLines[1].map(\.text).joined() == "value")
    }

    @Test
    @MainActor
    func `EditorState patches only the affected fallback highlight range`() throws {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.currentLanguage = "unknown_lang"
        state.fileContent = ["hello", "world", "tail"]
        state.highlightedLines = [
            [StyledSpan(text: "stale-first", style: .default)],
            [StyledSpan(text: "stale-second", style: .default)],
            [StyledSpan(text: "tail-sentinel", style: .default)],
        ]
        state.cursorRow = 1
        state.cursorCol = 0

        let mutation = try #require(
            TextOperations.deleteBackward(in: &state.textBuffer, at: &state.textCursor))
        state.textDidChange(mutation)

        #expect(state.fileContent == ["helloworld", "tail"])
        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "helloworld")
        #expect(state.highlightedLines[1][0].text == "tail-sentinel")
    }
}
