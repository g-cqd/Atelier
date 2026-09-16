import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct DiffRendererRegressionTests {
    /// Verifies that within a dirty range, cells where front == back are correctly
    /// skipped (e.g. when a cell is written then overwritten back to its original value).
    @Test
    func `cells overwritten back to original value are skipped`() {
        var front = ScreenBuffer(columns: 5, rows: 1)
        front.write("ABCDE", row: 0, col: 0, style: .default)

        var back = front
        back.dirty.clear()

        // Write a different value to col 2, then write it back
        back[0, 2] = Cell(character: "X", style: .default)
        back[0, 2] = Cell(character: "C", style: .default)

        // Col 2 is dirty but matches front
        #expect(back.dirty.isDirty(2))
        let output = DiffRenderer.render(front: front, back: back)
        #expect(output.isEmpty, "Cell overwritten back to original should produce no output")
    }

    /// Verifies that the DiffRenderer handles partial changes within a dirty range:
    /// some cells changed, some didn't (multi-renderer overlap scenario).
    @Test
    func `partial changes within dirty range emit only changed cells`() {
        var front = ScreenBuffer(columns: 10, rows: 1)
        front.write("ABCDEFGHIJ", row: 0, col: 0, style: .default)

        var back = front
        back.dirty.clear()

        // Change cells 2, 3 and 7 — leave the rest the same but mark range dirty
        back[0, 2] = Cell(character: "X", style: .default)
        back[0, 3] = Cell(character: "Y", style: .default)
        back[0, 7] = Cell(character: "Z", style: .default)

        let output = DiffRenderer.render(front: front, back: back)
        #expect(output.contains(0x58), "Changed cell 'X' should be emitted")  // X
        #expect(output.contains(0x59), "Changed cell 'Y' should be emitted")  // Y
        #expect(output.contains(0x5A), "Changed cell 'Z' should be emitted")  // Z
        #expect(!output.contains(0x41), "Unchanged cell 'A' should NOT be emitted")  // A
        #expect(!output.contains(0x45), "Unchanged cell 'E' should NOT be emitted")  // E
    }

    /// Verifies that wide characters within dirty ranges are handled correctly
    /// by the DiffRenderer's cell-skipping logic.
    @Test
    func `wide character changes are emitted correctly`() {
        let front = ScreenBuffer(columns: 10, rows: 1)
        var back = ScreenBuffer(columns: 10, rows: 1)

        // Write a wide character followed by narrow characters
        back.write("界AB", row: 0, col: 0, style: .default)

        let output = DiffRenderer.render(front: front, back: back)
        // Should contain the wide character's UTF-8 encoding
        let wideCharBytes = Array("界".utf8)
        var found = false
        for i in 0..<(output.count - wideCharBytes.count + 1) {
            if Array(output[i..<(i + wideCharBytes.count)]) == wideCharBytes {
                found = true
                break
            }
        }
        #expect(found, "Wide character should be emitted")
        #expect(output.contains(0x41), "Narrow 'A' after wide char should be emitted")
        #expect(output.contains(0x42), "Narrow 'B' should be emitted")
    }
}
