import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyStyle
import KittySyntax
import KittyTerminal
import Testing

@testable import KittyEditor

/// Terminal bytes reach the editor as the input loop hands them over, through `SequenceRouter` into `handleEvent`:
/// replies and oversized pastes never become keystrokes, and what they carry reaches the theme, the buffer or the
/// status bar.
@Suite
@MainActor
struct TerminalInputRoutingTests {
    @MainActor
    private struct Editor {
        let state: EditorState
        let pipeline: RenderPipeline

        /// Routes `bytes` as one read and hands every event to the editor.
        func receive(_ bytes: [UInt8]) {
            var router = SequenceRouter()
            for event in router.feedAll(bytes) {
                _ = handleEvent(event: event, state: state, pipeline: pipeline)
            }
        }
    }

    /// An empty buffer in editor mode, where a stray key would be typed.
    private func makeEditor(themeFromTerminal: Bool = false) -> Editor {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.syntax.themeFromTerminal = themeFromTerminal
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = [""]
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)), columns: 80, rows: 24)
        return Editor(state: state, pipeline: pipeline)
    }

    /// An OSC 52 clipboard reply carrying `payload`, base64 already applied.
    private func clipboardReply(_ payload: String) -> [UInt8] {
        Array("\u{1B}]52;c;\(payload)\u{1B}\\".utf8)
    }

    @Test
    func `Palette replies from the terminal apply the derived theme and type nothing`() {
        let editor = makeEditor(themeFromTerminal: true)

        editor.receive(Array("\u{1B}]10;rgb:e6e6/e6e6/e6e6\u{1B}\\\u{1B}]4;5;rgb:c8/1e/c8\u{07}\u{1B}[?62;22c".utf8))

        #expect(editor.state.syntaxTheme.style(for: "keyword").fg == .rgb(r: 200, g: 30, b: 200))
        #expect(editor.state.fileContent == [""])
    }

    @Test
    func `The clipboard reply to a paste request is pasted`() {
        let editor = makeEditor()
        editor.state.terminalWriter = { _ in }
        handlePasteRequest(state: editor.state)

        editor.receive(clipboardReply(Data("hello".utf8).base64EncodedString()))

        #expect(editor.state.fileContent == ["hello"])
    }

    @Test
    func `A clipboard reply that no paste request waits on is ignored`() {
        let editor = makeEditor()

        editor.receive(clipboardReply(Data("hello".utf8).base64EncodedString()))

        #expect(editor.state.fileContent == [""])
    }

    @Test
    func `An empty clipboard reply pastes nothing and says why`() {
        let editor = makeEditor()
        editor.state.terminalWriter = { _ in }
        handlePasteRequest(state: editor.state)

        editor.receive(clipboardReply(""))

        #expect(editor.state.fileContent == [""])
        #expect(editor.state.statusMessage == "Nothing to paste: the clipboard is empty or the terminal declined")
    }
}
