import AemiTestKit
import KittyStyle
import Testing

@testable import KittySyntax

/// `LineHighlights` reads and edits as the array of every line's spans it stands for, while storing one run of lines.
struct LineHighlightsTests {
    private static func spans(_ text: String) -> [StyledSpan] {
        [StyledSpan(text: text, style: .default)]
    }

    @Test
    func `lines never stored read as lines without spans`() {
        var lines = LineHighlights(unhighlightedLineCount: 1_000)
        lines.replaceSubrange(500 ..< 502, with: [Self.spans("a"), Self.spans("b")])

        #expect(lines.count == 1_000)
        #expect(lines[499].isEmpty)
        #expect(lines[500] == Self.spans("a"))
        #expect(lines[501] == Self.spans("b"))
        #expect(lines[502].isEmpty)
        #expect(lines.storedLines.count == 2)
    }

    @Test
    func `lines without spans put in place of others leave the stored run as it is`() {
        var lines = LineHighlights(unhighlightedLineCount: 100)
        lines.replaceSubrange(50 ..< 51, with: [Self.spans("kept")])

        lines.replaceSubrange(10 ..< 12, with: [[], [], []])
        lines.replaceSubrange(90 ..< 90, with: [[]])

        #expect(lines.count == 102)
        #expect(lines[51] == Self.spans("kept"))
        #expect(lines.storedLines.count == 1)
    }

    @Test
    func `equality compares lines, however each side stores them`() {
        var sparse = LineHighlights(unhighlightedLineCount: 3)
        sparse[1] = Self.spans("x")

        #expect(sparse == [[], Self.spans("x"), []])
        #expect(sparse != [[], Self.spans("x")])
        #expect(sparse != [[], Self.spans("y"), []])
    }

    /// Random edits, anywhere and of any size, applied to both a `LineHighlights` and the plain array it stands for.
    @Test(arguments: 0 ..< 8)
    func `random edits read back as the same edits on a plain array`(seed: UInt64) {
        var generator = SeededRNG(seed: seed)
        var model = [[StyledSpan]](repeating: [], count: 200)
        var lines = LineHighlights(unhighlightedLineCount: 200)
        for step in 0 ..< 400 {
            let lower = Int.random(in: 0 ... model.count, using: &generator)
            let upper = Int.random(in: lower ... min(model.count, lower + 5), using: &generator)
            let replacement: [[StyledSpan]] = (0 ..< Int.random(in: 0 ... 4, using: &generator))
                .map { index in
                    Bool.random(using: &generator) ? [] : Self.spans("\(step).\(index)")
                }
            if model.isEmpty || Int.random(in: 0 ..< 4, using: &generator) != 0 {
                model.replaceSubrange(lower ..< upper, with: replacement)
                lines.replaceSubrange(lower ..< upper, with: replacement)
            } else {
                let index = Int.random(in: 0 ..< model.count, using: &generator)
                model[index] = Self.spans("set \(step)")
                lines[index] = Self.spans("set \(step)")
            }
            #expect(lines.count == model.count)
        }
        #expect(Array(lines) == model)
        #expect(lines == LineHighlights(model))
    }
}
