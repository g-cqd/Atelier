import Testing

@testable import DiffRendering

/// What differs between a file's sides that its lines do not show.
struct FileDiffNoteTests {
    private func notes(
        _ old: String?,
        _ new: String?,
        modes: (String?, String?) = (nil, nil),
        differs: Bool = true
    ) -> [FileDiffNote] {
        FileDiffNote.notes(oldText: old, newText: new, oldMode: modes.0, newMode: modes.1, differs: differs)
    }

    @Test
    func `a file whose line endings change from LF to CRLF says so`() {
        #expect(notes("a\nb\n", "a\r\nb\r\n") == [.lineEndings(old: .lf, new: .crlf)])
    }

    @Test
    func `a file that gains or loses its final newline says so`() {
        #expect(notes("a\nb", "a\nb\n") == [.finalNewline(old: false, new: true)])
        #expect(notes("a\nb\n", "a\nb") == [.finalNewline(old: true, new: false)])
        #expect(FileDiffNote.finalNewline(old: false, new: true).text == "Newline added at end of file")
        #expect(FileDiffNote.finalNewline(old: true, new: false).text == "No newline at end of file")
    }

    @Test
    func `a mode change says so`() {
        #expect(notes("a\n", "a\n", modes: ("100644", "100755")) == [.mode(old: "100644", new: "100755")])
        #expect(notes("a\n", "a\n", modes: ("100644", nil), differs: false).isEmpty)
    }

    @Test
    func `sides that differ but read alike, as a byte-order mark, say that bytes the text does not show differ`() {
        #expect(notes("a\n", "a\n") == [.unshownBytes])
        #expect(notes("a\n", "a\n", differs: false).isEmpty)
    }

    @Test
    func `an added or a deleted file, or one with no line break, has no note on its breaks`() {
        #expect(notes(nil, "a\r\n").isEmpty)
        #expect(notes("a\r\n", nil).isEmpty)
        #expect(notes("a", "b").isEmpty)
        #expect(notes("", "a\n").isEmpty)
    }

    @Test
    func `line endings read as LF, CRLF, CR or mixed`() {
        #expect(FileDiffNote.lineEnding(of: "a\nb\n") == .lf)
        #expect(FileDiffNote.lineEnding(of: "a\r\nb\r\n") == .crlf)
        #expect(FileDiffNote.lineEnding(of: "a\rb\r") == .cr)
        #expect(FileDiffNote.lineEnding(of: "a\r\nb\n") == .mixed)
        #expect(FileDiffNote.lineEnding(of: "a") == nil)
    }
}
