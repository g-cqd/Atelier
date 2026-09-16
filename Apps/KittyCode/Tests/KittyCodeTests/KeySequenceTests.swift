import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import KittyText
import Testing

@testable import KittyEditor

// MARK: - KeymapResolver sequence resolution

@Suite
struct KeymapResolverSequenceTests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    private var vimConfig: KittyConfig {
        var config = KittyConfig()
        config.keybindingMode = .vim
        return config
    }

    // MARK: resolveSequence — .command

    @Test
    func `gg resolves to vimGotoFirstLine in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let gg = [stroke(AsciiKey.g), stroke(AsciiKey.g)]
        let result = resolver.resolveSequence(gg, context: .editorVimNormal)
        #expect(result == .command(.vimGotoFirstLine))
    }

    @Test
    func `dd resolves to vimDeleteLine in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let dd = [stroke(0x64), stroke(0x64)]
        let result = resolver.resolveSequence(dd, context: .editorVimNormal)
        #expect(result == .command(.vimDeleteLine))
    }

    @Test
    func `yy resolves to vimYankLine in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let yy = [stroke(AsciiKey.y), stroke(AsciiKey.y)]
        let result = resolver.resolveSequence(yy, context: .editorVimNormal)
        #expect(result == .command(.vimYankLine))
    }

    // MARK: resolveSequence — .partial

    @Test
    func `single g returns partial in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let g = [stroke(AsciiKey.g)]
        let result = resolver.resolveSequence(g, context: .editorVimNormal)
        #expect(result == .partial)
    }

    @Test
    func `single d returns partial in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let d = [stroke(0x64)]
        let result = resolver.resolveSequence(d, context: .editorVimNormal)
        #expect(result == .partial)
    }

    @Test
    func `single y returns partial in vim normal context`() {
        let resolver = KeymapResolver(config: vimConfig)
        let y = [stroke(AsciiKey.y)]
        let result = resolver.resolveSequence(y, context: .editorVimNormal)
        #expect(result == .partial)
    }

    // MARK: resolveSequence — .none

    @Test
    func `sequence with unrelated key returns none`() {
        let resolver = KeymapResolver(config: vimConfig)
        let hh = [stroke(AsciiKey.h), stroke(AsciiKey.h)]
        let result = resolver.resolveSequence(hh, context: .editorVimNormal)
        #expect(result == .none)
    }

    @Test
    func `sequence in non-vim context returns none`() {
        let resolver = KeymapResolver(config: vimConfig)
        let gg = [stroke(AsciiKey.g), stroke(AsciiKey.g)]
        let result = resolver.resolveSequence(gg, context: .editor)
        #expect(result == .none)
    }

    @Test
    func `empty sequence is treated as partial prefix`() {
        // An empty sequence is vacuously a prefix of every registered sequence.
        // In practice EventHandling never calls resolveSequence with an empty array;
        // candidate is always pending + [currentStroke], so this is an edge-case guard.
        let resolver = KeymapResolver(config: vimConfig)
        let result = resolver.resolveSequence([], context: .editorVimNormal)
        #expect(result == .partial)
    }
}

// MARK: - TextOperations.deleteLine

@Suite
struct TextOperationsDeleteLineTests {

    @Test
    func `deleteLine on multi-line buffer removes the target line`() {
        var buffer = TextBuffer(lines: ["first", "second", "third"])
        var cursor = TextCursor(row: 1, col: 0)
        _ = TextOperations.deleteLine(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["first", "third"])
        #expect(cursor.row == 1)
        #expect(cursor.col == 0)
    }

    @Test
    func `deleteLine on last line places cursor at new last line`() {
        var buffer = TextBuffer(lines: ["first", "second"])
        var cursor = TextCursor(row: 1, col: 3)
        _ = TextOperations.deleteLine(in: &buffer, at: &cursor)
        #expect(buffer.lines == ["first"])
        #expect(cursor.row == 0)
        #expect(cursor.col == 0)
    }

    @Test
    func `deleteLine on single-line buffer clears content but keeps the line`() {
        var buffer = TextBuffer(lines: ["only line"])
        var cursor = TextCursor(row: 0, col: 4)
        _ = TextOperations.deleteLine(in: &buffer, at: &cursor)
        #expect(buffer.lineCount == 1)
        #expect(buffer.line(at: 0) == "")
        #expect(cursor.row == 0)
        #expect(cursor.col == 0)
    }

    @Test
    func `deleteLine returns correct mutation range for removal`() {
        var buffer = TextBuffer(lines: ["a", "b", "c"])
        var cursor = TextCursor(row: 0, col: 0)
        let mutation = TextOperations.deleteLine(in: &buffer, at: &cursor)
        #expect(mutation.originalLineRange == 0..<1)
    }
}

// MARK: - vim command dispatch

@Suite
@MainActor
struct VimSequenceCommandDispatchTests {

    private func makeSUT(lines: [String] = ["alpha", "beta", "gamma"]) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        var config = KittyConfig()
        config.keybindingMode = .vim
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.vimMode = .normal
        state.fileContent = lines
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)),
            columns: 80,
            rows: 24
        )
        return (state, pipeline)
    }

    // MARK: vimGotoFirstLine

    @Test
    func `vimGotoFirstLine moves cursor to row 0 col 0`() {
        let sut = makeSUT()
        sut.state.cursorRow = 2
        sut.state.cursorCol = 3

        let result = dispatchCommand(.vimGotoFirstLine, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func `vimGotoFirstLine on already first line is a no-op`() {
        let sut = makeSUT()
        sut.state.cursorRow = 0
        sut.state.cursorCol = 2

        _ = dispatchCommand(.vimGotoFirstLine, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 0)
    }

    // MARK: vimDeleteLine

    @Test
    func `vimDeleteLine removes middle line and preserves surrounding lines`() {
        let sut = makeSUT(lines: ["alpha", "beta", "gamma"])
        sut.state.cursorRow = 1

        let result = dispatchCommand(.vimDeleteLine, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.fileContent == ["alpha", "gamma"])
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func `vimDeleteLine on last line moves cursor to new last line`() {
        let sut = makeSUT(lines: ["alpha", "beta"])
        sut.state.cursorRow = 1

        _ = dispatchCommand(.vimDeleteLine, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.fileContent == ["alpha"])
        #expect(sut.state.cursorRow == 0)
    }

    @Test
    func `vimDeleteLine on single line clears content`() {
        let sut = makeSUT(lines: ["only"])
        sut.state.cursorRow = 0

        _ = dispatchCommand(.vimDeleteLine, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.fileLineCount == 1)
        #expect(sut.state.fileLine(at: 0) == "")
    }

    @Test
    func `vimDeleteLine on empty file returns early`() {
        let sut = makeSUT(lines: [""])
        sut.state.cursorRow = 0
        let lineCountBefore = sut.state.fileLineCount

        let result = dispatchCommand(.vimDeleteLine, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(sut.state.fileLineCount == lineCountBefore)
    }

    // MARK: vimYankLine

    @Test
    func `vimYankLine writes line plus newline to clipboard`() {
        let sut = makeSUT(lines: ["hello", "world"])
        sut.state.cursorRow = 0
        var capturedBytes: [[UInt8]] = []
        sut.state.terminalWriter = { capturedBytes.append($0) }

        let result = dispatchCommand(.vimYankLine, state: sut.state, pipeline: sut.pipeline)

        #expect(result)
        #expect(!capturedBytes.isEmpty)
        #expect(sut.state.statusMessage == "Yanked line")
    }

    @Test
    func `vimYankLine does not modify buffer content`() {
        let sut = makeSUT(lines: ["alpha", "beta"])
        sut.state.cursorRow = 1
        let contentBefore = sut.state.fileContent
        sut.state.terminalWriter = { _ in }

        _ = dispatchCommand(.vimYankLine, state: sut.state, pipeline: sut.pipeline)

        #expect(sut.state.fileContent == contentBefore)
    }
}
