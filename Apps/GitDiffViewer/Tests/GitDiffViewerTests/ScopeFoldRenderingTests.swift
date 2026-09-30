import DiffCore
import Foundation
import Testing

@testable import DiffRendering

/// Folded scopes as the renderer cuts them (DIFF-03): after the compact view and the gaps, a fold keeps its first row
/// and puts one band in place of the rest, leaving every gap's key and revealed lines as they were.
struct ScopeFoldRenderingTests {
    static let old = """
        struct S {
            func f() {
                let a = 1
            }
            func g() {
                let b = 2
            }
            func h() {
                let c = 3
            }
        }

        """
    static let new =
        old.replacingOccurrences(of: "let a = 1", with: "let a = 10").replacingOccurrences(of: "c = 3", with: "c = 30")

    /// The new side's `f`, lines 1 to 3, and the whole of `S`, lines 0 to 10.
    static let f = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 1)
    static let s = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 0)

    static func render(
        folds: [ScopeFoldKey: Int], layout: RenderLayout = .full, compacts: Bool = false,
        sides: Set<RenderedSide> = [.unified]
    ) -> RenderedDiff {
        let prepared = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: old, newText: new, language: .swift), granularity: .word)
        return DiffRenderer.render(
            prepared: [prepared],
            options: DiffRenderer.Options(sides: sides, compactsInline: compacts, foldedScopes: folds), layout: layout,
            withHeaders: false)
    }

    /// The text of `row` in `text`.
    static func line(_ row: Int, of text: RenderedText) -> String {
        let string = text.attributed.string as NSString
        let end = row + 1 < text.lineStarts.count ? text.lineStarts[row + 1] - 1 : string.length
        return string.substring(with: NSRange(location: text.lineStarts[row], length: end - text.lineStarts[row]))
    }

    @Test
    func `a fold keeps its first row and puts one band with its closing line in place of the rest`() throws {
        let text = try #require(Self.render(folds: [Self.f: 3]).unified)

        let fold = try #require(text.folds.first)
        #expect(text.folds.count == 1)
        #expect(text.rows[fold.firstRow].newNumber == 2)
        #expect(fold.bandRow == fold.firstRow + 1)
        #expect(Self.line(fold.bandRow, of: text) == "    ••• }")
        #expect(fold.holdsChange)
        #expect(text.rows[fold.bandRow + 1].newNumber == 5)
        #expect(!text.rows.contains { [3, 4].contains($0.newNumber ?? 0) || $0.oldNumber == 3 })
    }

    @Test
    func `a fold over gaps hides them, and unfolding brings back their keys and revealed lines`() throws {
        let revealed = RenderLayout.changes(
            context: 1, expansions: [GapKey(fileIndex: 0, gapIndex: 0): GapExpansion(above: 1)])
        let open = try #require(Self.render(folds: [:], layout: revealed).unified)
        let g = [ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 4): 6]
        let inner = try #require(Self.render(folds: g, layout: revealed).unified)
        let folded = try #require(Self.render(folds: [Self.s: 10], layout: revealed).unified)

        // `g` lies in a gap: its first row does not show, so its fold does nothing.
        #expect(inner.folds.isEmpty)
        #expect(inner.gaps.map(\.marker.key) == open.gaps.map(\.marker.key))
        let fold = try #require(folded.folds.first)
        #expect(folded.rows.count == 2)
        #expect(fold.holdsChange)
        #expect(folded.gaps.allSatisfy { $0.boundary <= fold.firstRow })
        #expect(open.gaps.map(\.marker.key.gapIndex) == [1, 2])
        #expect(open.rows.first?.newNumber == 1)
    }

    @Test
    func `the compact view's changes inside a fold give way to its band, which tells they are there`() throws {
        let open = try #require(Self.render(folds: [:], compacts: true).unified)
        let folded = try #require(Self.render(folds: [Self.f: 3], compacts: true).unified)

        #expect(open.changes.count == 2)
        #expect(folded.changes.map(\.key.changeIndex) == [1])
        #expect(folded.folds.first?.holdsChange == true)
    }

    @Test
    func `side by side, both panes fold the rows the clicked side's scope covers`() throws {
        let diff = Self.render(folds: [Self.f: 3], sides: [.old, .new])
        let old = try #require(diff.old)
        let new = try #require(diff.new)

        #expect(old.rows.count == new.rows.count)
        #expect(old.folds.map(\.bandRow) == new.folds.map(\.bandRow))
        let band = try #require(new.folds.first?.bandRow)
        #expect(Self.line(band, of: new) == "    ••• }")
        #expect(Self.line(band, of: old) == "    •••")
    }
}
