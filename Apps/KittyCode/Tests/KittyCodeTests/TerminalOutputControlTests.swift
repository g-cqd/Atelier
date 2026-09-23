import KittyCodecs
import KittyRenderer
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

/// Whether `scalar` is a C0 control, DEL or a C1 control, written out here rather than taken from the code under test.
private func isControlScalar(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value < 0x20 || (0x7F ... 0x9F).contains(scalar.value)
}

/// What a frame shows once its CSI sequences, the only commands the cell encoder writes, are taken out, and every
/// other control scalar in it: an ESC that starts anything but a CSI, a BEL, DEL or a C1 control.
private struct FrameText {
    private(set) var text = ""
    private(set) var strayControls: [Unicode.Scalar] = []

    init(_ bytes: some Collection<UInt8>) {
        var scalars = String(decoding: bytes, as: UTF8.self).unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            if scalar == "\u{1B}" {
                guard let introducer = scalars.next(), introducer == "[" else {
                    strayControls.append(scalar)
                    continue
                }
                // Parameter and intermediate bytes up to one final byte.
                while let next = scalars.next(), !(0x40 ... 0x7E).contains(next.value) {
                    if !(0x20 ... 0x3F).contains(next.value) { strayControls.append(next) }
                }
            } else if isControlScalar(scalar) {
                strayControls.append(scalar)
            } else {
                text.unicodeScalars.append(scalar)
            }
        }
    }
}

/// A repository's file names and contents are attacker input: a name carrying `ESC ] 52` writes the clipboard in
/// kitty, and a C1 OSC or CSI in a file is a command too, so none may reach the terminal as bytes.
@Suite
@MainActor
struct TerminalOutputControlTests {
    /// An OSC 52 clipboard write ended by BEL, a DCS request ended by ESC \, DEL, and C1 OSC and ST.
    static let hostileName = "x\u{1B}]52;c;aGk=\u{07}\u{1B}P+q\u{1B}\\\u{7F}\u{9D}52;c;aGk=\u{9C}.txt"
    /// A line holding an OSC 52 clipboard write, a C1 CSI and DEL.
    static let hostileLine = "a\u{1B}]52;c;aGk=\u{07}b\u{9B}2Jc\u{7F}d"

    /// `text` as the terminal must show it, each control character as the replacement glyph.
    private static func shown(_ text: String) -> String {
        String(text.map { $0.unicodeScalars.contains(where: isControlScalar) ? "\u{FFFD}" : $0 })
    }

    @Test
    func `a file whose name and content hold escape sequences reaches the terminal without a control byte`() throws {
        let connection = MockTerminalConnection(size: TerminalSize(columns: 100, rows: 8))
        let pipeline = RenderPipeline(connection: connection, columns: 100, rows: 8)
        let state = EditorTestHarness.make(columns: 100, rows: 8, tabRibbon: .top, sidebarCollapsed: true).state
        state.bufferManager.open(
            filePath: "/tmp/" + Self.hostileName, fileName: Self.hostileName, content: Self.hostileLine, language: nil)
        state.restoreStateFromActiveBuffer()
        state.refreshHighlights()

        pipeline.beginFrame()
        renderShellLayout(pipeline: pipeline, state: state)
        try pipeline.flush()

        let frame = FrameText(connection.writtenOutput)
        #expect(frame.strayControls.isEmpty)
        #expect(frame.text.contains(Self.shown(Self.hostileName)))
        #expect(frame.text.contains("a ]52;c;aGk= b 2Jc d"))
    }

    @Test
    func `a tab named with escape sequences is drawn without a control byte`() {
        var buffer = ScreenBuffer(columns: 60, rows: 1)
        let ribbon = TabRibbon(tabs: [TabRibbon.Tab(name: Self.hostileName, isDirty: true)], activeIndex: 0)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 60, height: 1))

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text.hasPrefix(" " + Self.shown(Self.hostileName) + " "))
    }

    @Test
    func `styled text holding escape sequences is drawn without a control byte`() {
        var buffer = ScreenBuffer(columns: 60, rows: 1)
        let view = StyledTextView([
            .init(text: Self.hostileLine, style: .default), .init(text: Self.hostileName, style: Style(bold: true))
        ])
        view.render(to: &buffer, in: Rect(x: 0, y: 0, width: 60, height: 1))

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text.hasPrefix(Self.shown(Self.hostileLine) + Self.shown(Self.hostileName)))
    }
}
