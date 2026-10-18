import AtelierText
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyStyle
import KittyTerminal
import TerminalKitCodecs
import TerminalKitIO
import TerminalKitInput
import TerminalKitRender
import TerminalKitStyle
import TerminalKitText
import Testing

@Suite("Terminal compatibility modules share one implementation")
struct TerminalCompatibilityTests {
    @Test func `codec events keep their canonical type through the compatibility import`() {
        let event: TerminalKitCodecs.KeyEvent = KittyCodecs.KeyEvent(keyCode: 97, modifiers: .ctrl)
        #expect(event == TerminalKitCodecs.KeyEvent(keyCode: 97, modifiers: .ctrl))
    }

    @Test func `input events carry the same key event across module names`() throws {
        let event: TerminalKitInput.InputEvent = KittyInput.InputEvent.key(KittyCodecs.KeyEvent(keyCode: 98))
        guard case .key(let key) = event else {
            Issue.record("the compatibility input changed a key event's case")
            return
        }
        #expect(key == TerminalKitCodecs.KeyEvent(keyCode: 98))
    }

    @Test func `Atelier text is the shared rope rather than a duplicate nominal type`() {
        let rope: TerminalKitText.Rope = AtelierText.Rope("first\nsecond")
        #expect(rope.lineCount == 2)
    }

    @Test @MainActor func `the renderer uses the shared connection and style through the shims`() throws {
        let connection: TerminalKitIO.MockTerminalConnection = KittyTerminal.MockTerminalConnection()
        let pipeline: TerminalKitRender.RenderPipeline = KittyRenderer.RenderPipeline(
            connection: connection, columns: 10, rows: 2)
        let style: TerminalKitStyle.Style = KittyStyle.Style.default
        pipeline.beginFrame()
        pipeline.buffer.write("shared", row: 0, col: 0, style: style)
        try pipeline.flush()
        let output = connection.writtenOutput
        #expect(Array(output.prefix(EscapeSequences.beginSyncUpdate.count)) == EscapeSequences.beginSyncUpdate)
        #expect(Array(output.suffix(EscapeSequences.endSyncUpdate.count)) == EscapeSequences.endSyncUpdate)
    }
}
