import AtelierText
import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

/// Whether `scalar` is a C0 control, DEL or a C1 control, written out here rather than taken from the code under test.
private func isControlScalar(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value < 0x20 || (0x7F ... 0x9F).contains(scalar.value)
}

/// Whether `character` holds a control scalar.
private func isControlCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: isControlScalar)
}

/// What a frame shows once its CSI sequences, the only commands the cell encoder writes, are taken out, and every
/// other control scalar in it: an ESC that starts anything but a CSI, a BEL, DEL or a C1 control.
struct FrameText {
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

/// Text reaches the terminal only through cells, so no writer may leave a control character in one: an ESC opens an
/// OSC 52 clipboard write or a DCS command, a BEL or a C1 ST ends it, and a C1 CSI or OSC is a command of its own.
@Suite
struct ControlCharacterFrameTests {
    /// Every C0 control, DEL and every C1 control.
    static let controls = (Array(0x00 ... 0x1F) + [0x7F] + Array(0x80 ... 0x9F))
        .compactMap { Unicode.Scalar(UInt32($0)) }

    /// An OSC 52 clipboard write ended by BEL, a DCS request ended by ESC \, a CSI, DEL, and the C1 forms of OSC, ST
    /// and CSI, as a file name or a line of a file could hold them.
    static let hostile = "a\u{1B}]52;c;aGk=\u{07}b\u{1B}P+q\u{1B}\\c\u{1B}[31md\u{7F}e\u{9D}52;c;aGk=\u{9C}f\u{9B}2Jg"

    /// `hostile` as the terminal must show it, each control character as the replacement glyph.
    static let hostileShown = String(hostile.map { isControlCharacter($0) ? "\u{FFFD}" : $0 })

    /// Every one- and two-byte scalar, which covers the ASCII fast path and every control, plus clusters.
    @Test
    func `a character is a control when one of its scalars is, per the shared predicate`() {
        let scalars = (0 ... 0x7FF as ClosedRange<UInt32>).compactMap(Unicode.Scalar.init)
        let mismatches = scalars.filter { ScreenBuffer.isControl(Character($0)) != TextSanitizer.isControl($0) }

        #expect(mismatches.isEmpty)
        #expect(ScreenBuffer.isControl("\r\n"))
        #expect(!ScreenBuffer.isControl("e\u{301}") && !ScreenBuffer.isControl("\u{1F468}\u{200D}\u{1F469}"))
    }

    @Test(arguments: controls)
    func `a control stored through the subscript is sent as the replacement glyph`(control: Unicode.Scalar) {
        var buffer = ScreenBuffer(columns: 3, rows: 1)
        buffer[0, 1] = Cell(character: Character(control))

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text == " \u{FFFD} ")
    }

    @Test(arguments: controls)
    func `a control filled over a region is sent as the replacement glyph`(control: Unicode.Scalar) {
        var buffer = ScreenBuffer(columns: 4, rows: 2)
        buffer.fill(row: 0, col: 1, width: 2, height: 2, cell: Cell(character: Character(control)))

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text == " \u{FFFD}\u{FFFD}  \u{FFFD}\u{FFFD} ")
    }

    @Test(arguments: controls)
    func `a control written in a string is sent as the replacement glyph`(control: Unicode.Scalar) {
        var buffer = ScreenBuffer(columns: 4, rows: 1)
        buffer.write("x\(Character(control))y", row: 0, col: 0, style: .default)

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text == "x\u{FFFD}y ")
    }

    @Test
    func `escape sequences written in a string reach the frame as text only`() {
        var buffer = ScreenBuffer(columns: 60, rows: 1)
        buffer.write(Self.hostile, row: 0, col: 0, style: .default)

        let frame = FrameText(DiffRenderer.renderFull(buffer))

        #expect(frame.strayControls.isEmpty)
        #expect(frame.text.hasPrefix(Self.hostileShown))
    }

    @Test
    @MainActor
    func `the bytes a pipeline sends carry no control from any writer`() throws {
        let connection = MockTerminalConnection(size: TerminalSize(columns: 60, rows: 3))
        let pipeline = RenderPipeline(connection: connection, columns: 60, rows: 3)
        pipeline.beginFrame()
        pipeline.buffer.write(Self.hostile, row: 0, col: 0, style: .default)
        for (column, character) in Self.hostile.enumerated() {
            pipeline.buffer[1, column] = Cell(character: character)
        }
        pipeline.buffer.fill(row: 2, col: 0, width: 4, height: 1, cell: Cell(character: "\u{9B}"))

        try pipeline.flush()

        let frame = FrameText(connection.writtenOutput)
        #expect(frame.strayControls.isEmpty)
        #expect(frame.text.hasPrefix(Self.hostileShown))
    }

    @Test
    func `a continuation cell keeps its placeholder, which the frame never sends`() {
        var buffer = ScreenBuffer(columns: 4, rows: 1)
        buffer.write("\u{754C}", row: 0, col: 0, style: .default)
        buffer[0, 3] = .continuation

        #expect(buffer[0, 1] == .continuation)
        #expect(buffer[0, 3] == .continuation)
        let frame = FrameText(DiffRenderer.renderFull(buffer))
        #expect(frame.strayControls.isEmpty)
        #expect(frame.text == "\u{754C} ")
    }

    @Test
    func `printable ASCII sends the same frame whether written as a string or cell by cell`() {
        let printable = String((0x20 ... 0x7E).map { Character(Unicode.Scalar(UInt8($0))) })
        let styles = [Style.default, Style(fg: .rgb(r: 1, g: 2, b: 3), bold: true), Style(bg: .rgb(r: 9, g: 8, b: 7))]
        var written = ScreenBuffer(columns: 100, rows: styles.count)
        var reference = ScreenBuffer(columns: 100, rows: styles.count)
        for (row, style) in styles.enumerated() {
            // Starting further right each row, so the text runs past the edge.
            let start = row * 4
            written.write(printable, row: row, col: start, style: style)
            for (offset, character) in printable.enumerated() {
                reference[row, start + offset] = Cell(character: character, style: style)
            }
        }

        #expect(written.cells == reference.cells)
        #expect(DiffRenderer.renderFull(written) == DiffRenderer.renderFull(reference))
        let blank = ScreenBuffer(columns: 100, rows: styles.count)
        #expect(DiffRenderer.render(front: blank, back: written) == DiffRenderer.render(front: blank, back: reference))
    }

    /// Mixes of ASCII with combining marks, wide characters, emoji sequences, controls and zero-width characters,
    /// where the ASCII fast path must hand over to grapheme breaking at the right byte.
    static let mixedText = [
        "plain text only", "\u{E9}t\u{E9}", "\u{FF8A}\u{FF9D}ok",
        "e\u{301}x", "x\u{301}\u{302}y", "\u{301}lead", "a\u{200D}b", "x\u{FE0F}y", "a\u{200B}b",
        "a\r\nb", "tab\there", "\u{1B}[31mred", "a\u{0}b",
        "\u{754C}a\u{754C}", "\u{FF26}\u{FF55}ll", "ab\u{1100}\u{1161}cd",
        "\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}",
        "\u{1F1EB}\u{1F1F7}x\u{1F1E9}\u{1F1EA}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}z"
    ]

    @Test(arguments: mixedText, [0, 5, 11])
    func `write gives any text the cells the per-character loop gives`(text: String, column: Int) {
        var written = ScreenBuffer(columns: 12, rows: 1)
        var reference = ScreenBuffer(columns: 12, rows: 1)
        // Wide characters underneath, so narrow text must clear the continuation cells it leaves behind.
        Self.referenceWrite("\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}", into: &written, column: 0)
        Self.referenceWrite("\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}\u{754C}", into: &reference, column: 0)

        written.write(text, row: 0, col: column, style: .default)
        Self.referenceWrite(text, into: &reference, column: column)

        #expect(written.cells == reference.cells)
    }

    /// The per-character loop `write` ran before its ASCII fast path, through the subscript.
    private static func referenceWrite(_ string: String, into buffer: inout ScreenBuffer, column: Int) {
        var col = column
        for raw in string {
            let character: Character = isControlCharacter(raw) ? "\u{FFFD}" : raw
            let width = UnicodeWidth.displayWidth(of: character)
            guard width > 0 else { continue }
            if width == 2 {
                guard col + 1 < buffer.columns else { break }
                buffer[0, col] = Cell(character: character, width: 2)
                buffer[0, col + 1] = .continuation
                col += 2
            } else {
                guard col < buffer.columns else { break }
                buffer[0, col] = Cell(character: character)
                if col + 1 < buffer.columns, buffer[0, col + 1].width == 0 { buffer[0, col + 1] = .empty }
                col += 1
            }
        }
    }

    @Test
    func `a fill reaching past the buffer stops at its edges`() {
        var buffer = ScreenBuffer(columns: 4, rows: 3)
        buffer.fill(row: 1, col: 2, width: .max, height: .max, cell: Cell(character: "#"))

        #expect(buffer.cells.map(\.character) == Array("    " + "  ##" + "  ##"))
    }
}
