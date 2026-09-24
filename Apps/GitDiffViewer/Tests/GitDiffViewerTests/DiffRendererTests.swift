import AemiRuntime
import AppKit
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

struct DiffRendererTests {
    private let old = (1 ... 30).map { "line \($0)" }.joined(separator: "\n") + "\n"
    private var new: String {
        old.replacingOccurrences(of: "line 10\n", with: "line ten\n").replacingOccurrences(of: "line 25\n", with: "")
    }

    @Test
    func `the changes layout keeps hunks with context and marks the hidden rows between them`() throws {
        let rendered = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
        )
        let unified = try #require(rendered.unified)
        #expect(unified.gaps.map(\.marker.hiddenRows) == [7, 10, 3])
        #expect(rendered.unifiedChangeStarts.count == 2)
        #expect(unified.rows.first?.oldNumber == 8)
    }

    @Test
    func `a file without a change shows every row when the layout asks for it, and a changed file keeps its gaps`()
        throws
    {
        let whole = try #require(
            DiffRenderer.render(
                oldText: old, newText: old, language: .plain,
                layout: .changes(context: 2, expansions: [:], wholeWhenUnchanged: true)
            )
            .unified)
        #expect(whole.rows.count == 30)
        #expect(whole.gaps.isEmpty)

        let hidden = try #require(
            DiffRenderer.render(
                oldText: old, newText: old, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        #expect(hidden.rows.isEmpty)

        let changed = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain,
                layout: .changes(context: 2, expansions: [:], wholeWhenUnchanged: true)
            )
            .unified)
        #expect(changed.gaps.map(\.marker.hiddenRows) == [7, 10, 3])
    }

    @Test
    func `a hidden run takes no row of its own`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        // Two hunks: lines 8 to 12 with line 10 changed, then lines 23 to 27 with line 25 removed.
        #expect(rendered.rows.count == 11)
        #expect(rendered.lineStarts.count == 11)
        #expect(rendered.rows.allSatisfy { $0.oldNumber != nil || $0.newNumber != nil })
        #expect(!rendered.attributed.string.contains("hidden"))
    }

    @Test
    func `line numbers jump across a hidden run, on the boundary its gap lies on`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let between = try #require(rendered.gaps.first { !$0.marker.isLeading && !$0.marker.isTrailing })
        #expect(rendered.rows[between.boundary - 1].oldNumber == 12)
        #expect(rendered.rows[between.boundary].oldNumber == 23)
    }

    @Test
    func `a trailing gap lies on the boundary below the last row`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let last = try #require(rendered.gaps.last)
        #expect(last.marker.isTrailing)
        #expect(last.boundary == rendered.rows.count)
        #expect(rendered.rows.last?.oldNumber == 27)
    }

    @Test
    func `changes on either side of a hidden run stay two changes`() throws {
        let old = "line1\nline2AAAA\nline3\nline4\nline5\nline6AAAA\nline7\n"
        let new = "line1\nline2BBBB\nline3\nline4\nline5\nline6BBBB\nline7\n"
        let rendered = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 0, expansions: [:]))
        // With no context, the rows of the two changes touch across the gap between them.
        #expect(rendered.splitChangeStarts == [0, 1])
        #expect(rendered.unifiedChangeStarts == [0, 2])
    }

    /// The paragraph spacing after each row of `text`, and before its first.
    private func spacings(of text: RenderedText) -> (before: CGFloat, after: [CGFloat]) {
        let style = { (offset: Int) in
            text.attributed.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
        }
        return (style(0)?.paragraphSpacingBefore ?? -1, text.lineStarts.map { style($0)?.paragraphSpacing ?? -1 })
    }

    @Test(arguments: [0.0, 1.4])
    func `a gap's band is exactly one row tall, whatever the line height`(multiple: Double) throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, lineHeightMultiple: multiple,
                layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        #expect(rendered.gapBandHeight == rendered.lineHeight)
    }

    @Test
    func `a gap between two rows takes its band as the paragraph spacing of the row above`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let between = try #require(rendered.gaps.first { !$0.marker.isLeading && !$0.marker.isTrailing })
        let after = spacings(of: rendered).after

        #expect(after[between.boundary - 1] == rendered.gapBandHeight)
        #expect(after.enumerated().allSatisfy { $0.offset == between.boundary - 1 || $0.element == 0 })
        #expect(rendered.bandSpacing(afterRow: between.boundary - 1) == rendered.gapBandHeight)
    }

    @Test
    func `the bands of the gaps at the top and the end of the file lie outside the text`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let spacing = spacings(of: rendered)

        #expect(rendered.bandAbove == rendered.gapBandHeight)
        #expect(rendered.bandBelow == rendered.gapBandHeight)
        #expect(spacing.before == 0)
        #expect(spacing.after.last == 0)
    }

    @Test
    func `the rows' unwrapped height counts the bands between them`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        #expect(
            rendered.unwrappedTextHeight == CGFloat(rendered.rows.count) * rendered.lineHeight + rendered.gapBandHeight)
    }

    @Test
    func `a gap offering no handle takes no band`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: old, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        #expect(rendered.gaps.map(\.hasBand) == [false])
        #expect(rendered.bandAbove == 0)
        #expect(rendered.unwrappedTextHeight == rendered.lineHeight)
    }

    @Test
    func `both split panes take the same bands`() throws {
        let diff = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:]))
        let oldSide = try #require(diff.old)
        let newSide = try #require(diff.new)

        #expect(spacings(of: oldSide).after == spacings(of: newSide).after)
        #expect(oldSide.bandAbove == newSide.bandAbove)
        #expect(oldSide.bandBelow == newSide.bandBelow)
    }

    @Test
    func `expanding a gap reveals its rows`() {
        let key = GapKey(fileIndex: 0, gapIndex: 0)
        let rendered = DiffRenderer.render(
            oldText: old, newText: new, language: .plain,
            layout: .changes(context: 2, expansions: [key: GapExpansion(below: 0, above: 4)])
        )
        #expect(rendered.unified?.gaps.first?.marker.hiddenRows == 3)
        #expect(rendered.unified?.rows.first?.oldNumber == 4)
    }

    @Test
    func `a leading gap lies on the boundary above the first row`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let first = try #require(rendered.gaps.first)
        #expect(first.boundary == 0)
        #expect(first.marker.isLeading)
        #expect(first.marker.hiddenRows == 7)
    }

    @Test
    func `the split panes record the same gaps on the same boundaries`() throws {
        let diff = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:]))
        let oldSide = try #require(diff.old)
        let newSide = try #require(diff.new)
        #expect(oldSide.gaps.count == 3)
        #expect(oldSide.gaps == newSide.gaps)
    }

    @Test
    func `gaps looked up by boundary are those on the boundaries asked for`() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old, newText: new, language: .plain, layout: .changes(context: 2, expansions: [:])
            )
            .unified)
        let boundaries = rendered.gaps.map(\.boundary)
        try #require(boundaries.count == 3)
        #expect(rendered.gaps(on: 0 ... 0).map(\.boundary) == [0])
        #expect(rendered.gaps(on: 1 ... boundaries[1]).map(\.boundary) == [boundaries[1]])
        #expect(rendered.gaps(on: (boundaries[1] + 1) ... (boundaries[2] - 1)).isEmpty)
        #expect(rendered.gaps(on: 0 ... rendered.rows.count).map(\.boundary) == boundaries)
    }

    @Test
    func `several files are rendered one after another with a header each`() throws {
        let files = [
            FileDiffInput(title: "a.txt", oldText: "x\n", newText: "y\n", language: .plain),
            FileDiffInput(title: "b.txt", oldText: "same\n", newText: "same\nmore\n", language: .plain)
        ]
        let rendered = DiffRenderer.renderCombined(files: files, context: 1, expansions: [:])
        let rows = try #require(rendered.unified?.rows)
        #expect(rows.filter { $0.kind == .header }.count == 2)
        #expect(rows.first?.kind == .header)
        #expect(rendered.changeCount == 2)
        #expect(rows.last?.kind == .added)
        #expect(rows.last?.fileIndex == 1)
        #expect(rendered.isCombined)
        #expect(rendered.old?.rows.count == rendered.new?.rows.count)
        #expect(rendered.old?.rows.filter { $0.kind == .header }.count == 2)
    }

    @Test
    func `rendering only the requested sides leaves the others nil`() {
        var options = DiffRenderer.Options()
        options.sides = [.unified]
        let rendered = DiffRenderer.renderCombined(
            files: [FileDiffInput(title: "a", oldText: "x\n", newText: "y\n", language: .plain)], options: options,
            context: 1, expansions: [:])
        #expect(rendered.unified != nil)
        #expect(rendered.old == nil)
        #expect(rendered.new == nil)
    }

    @Test
    func `rendering is deterministic under concurrency`() async throws {
        let prepared = PreparedDiff(
            FileDiffInput(title: "a", oldText: old, newText: new, language: .swift), granularity: .syntax)
        let layout = RenderLayout.changes(context: 2, expansions: [:])
        let results = try await mapConcurrently(Array(0 ..< 16), limit: 8) { _ in
            DiffRenderer.render(
                prepared: [prepared], options: DiffRenderer.Options(), layout: layout, withHeaders: false
            )
            .unified?
            .attributed.string
        }
        let reference =
            DiffRenderer.render(
                prepared: [prepared], options: DiffRenderer.Options(), layout: layout, withHeaders: false
            )
            .unified?
            .attributed.string
        #expect(results.allSatisfy { $0 == reference })
    }

    @Test
    func `an unterminated string that runs to the closing newline is clipped to its lines`() {
        let text = "let s = \"\"\"\n}\n"
        let lines: [Substring] = ["let s = \"\"\"", "}"]
        let byLine = DiffRenderer.tokensByLine(text: text, lines: lines, language: .swift)
        #expect(byLine.count == 2)
        #expect(byLine[1].map(\.byteRange) == [0 ..< 1])
        #expect(byLine[1].map(\.role) == [.string])
        #expect(byLine[0].allSatisfy { $0.byteRange.upperBound <= 11 })
    }
}
