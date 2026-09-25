import DiffCore
import Foundation
import Testing

@testable import DiffRendering

/// The compact inline view's rendering (book DIFF-04): the new file with each change folded into it, a marker per
/// change, a change disclosed in place, and the isolated-changes mode's gaps kept around them.
struct CompactInlineRenderTests {
    /// Thirty lines: line 5 modified, line 12 removed, and a line added after line 20.
    private static let sides: (old: String, new: String) = {
        let old = (1 ... 30).map { "let value\($0) = \($0)" }
        var new = old
        new[4] = "let value5 = five"
        new.remove(at: 11)
        new.insert("let added = true", at: 19)
        return (old.joined(separator: "\n") + "\n", new.joined(separator: "\n") + "\n")
    }()

    private static func render(
        disclosing disclosed: Set<Int> = [], layout: RenderLayout = .full, compact: Bool = true
    ) throws -> RenderedText {
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: sides.old, newText: sides.new, language: .plain), granularity: .word)
        let options = DiffRenderer.Options(
            sides: [.unified], compactsInline: compact,
            disclosedChanges: Set(disclosed.map { ChangeKey(fileIndex: 0, changeIndex: $0) }))
        return try #require(
            DiffRenderer.render(prepared: [prepared], options: options, layout: layout, withHeaders: false).unified)
    }

    private static func lines(of text: RenderedText) -> [String] {
        text.attributed.string.components(separatedBy: "\n")
    }

    @Test
    func `folded, the inline side reads as the new file, untinted and numbered on the new side`() throws {
        let text = try Self.render()

        #expect(Self.lines(of: text) == Self.sides.new.components(separatedBy: "\n").dropLast())
        #expect(text.rows.allSatisfy { $0.kind == .context })
        #expect(text.rows.map(\.newNumber) == Array(1 ... 30))
    }

    @Test
    func `each change has a marker: a bar over its new rows, and none for a removal but its boundary`() throws {
        let text = try Self.render()

        #expect(text.changes.map(\.kind) == [.modified, .removed, .added])
        #expect(text.changes.map(\.rows) == [4 ..< 5, 11 ..< 11, 19 ..< 20])
        #expect(text.changes.allSatisfy { !$0.isDisclosed })
    }

    @Test
    func `a disclosed change shows its removed rows above its added ones, tinted, in place`() throws {
        let text = try Self.render(disclosing: [0])

        let shown = Self.lines(of: text)[3 ... 6]
        #expect(shown == ["let value4 = 4", "let value5 = 5", "let value5 = five", "let value6 = 6"])
        #expect(text.rows[4].kind == .removed)
        #expect(text.rows[5].kind == .added)
        #expect(text.changes.map(\.rows) == [4 ..< 6, 12 ..< 12, 20 ..< 21])
        #expect(text.changes.map(\.isDisclosed) == [true, false, false])
    }

    @Test
    func `a disclosed removal takes its rows back where the lines were`() throws {
        let text = try Self.render(disclosing: [1])

        #expect(Self.lines(of: text)[11] == "let value12 = 12")
        #expect(text.rows[11].kind == .removed)
        #expect(text.changes[1].rows == 11 ..< 12)
    }

    @Test(arguments: [0, 2])
    func `isolated, every change keeps its context and its marker`(context: Int) throws {
        let text = try Self.render(layout: .changes(context: context, expansions: [:]))

        #expect(text.changes.map(\.kind) == [.modified, .removed, .added])
        // Each change has a row of its own or, for a folded removal, the row after it.
        for change in text.changes {
            #expect(text.rows.indices.contains(change.rows.lowerBound), "\(change.kind) lies by a shown row")
        }
        #expect(text.gaps.count == 4)
    }

    @Test
    func `disclosing a change keeps the gaps, their keys and the rows they hide`() throws {
        let layout = RenderLayout.changes(context: 2, expansions: [:])
        let folded = try Self.render(layout: layout)
        let disclosed = try Self.render(disclosing: [0, 1, 2], layout: layout)

        #expect(disclosed.gaps.map(\.marker) == folded.gaps.map(\.marker))
    }

    @Test
    func `lines revealed around a gap stay revealed when a change is disclosed`() throws {
        let key = try #require(try Self.render(layout: .changes(context: 2, expansions: [:])).gaps.dropFirst().first)
            .marker.key
        let layout = RenderLayout.changes(context: 2, expansions: [key: GapExpansion(below: 2)])

        let folded = try Self.render(layout: layout)
        let disclosed = try Self.render(disclosing: [0], layout: layout)

        let hidden = { (text: RenderedText) in text.gaps.first { $0.marker.key == key }?.marker.hiddenRows }
        #expect(hidden(disclosed) == hidden(folded))
        #expect(disclosed.rows.count == folded.rows.count + 1)
    }

    @Test
    func `each change starts where navigation lands: its first row, or the row after a folded removal`() throws {
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: Self.sides.old, newText: Self.sides.new, language: .plain),
            granularity: .word)
        let diff = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified], compactsInline: true),
            layout: .full, withHeaders: false)

        #expect(diff.unifiedChangeStarts == [4, 11, 19])
    }

    @Test
    func `a file with no new line shows its changes disclosed`() throws {
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: "a\nb\n", newText: "", language: .plain), granularity: .word)
        let text = try #require(
            DiffRenderer.render(
                prepared: [prepared], options: DiffRenderer.Options(sides: [.unified], compactsInline: true),
                layout: .full, withHeaders: false
            )
            .unified)

        #expect(text.rows.map(\.kind) == [.removed, .removed])
        #expect(text.changes.map(\.isDisclosed) == [true])
    }

    @Test
    func `off, the inline side shows every change as the inline view does`() throws {
        let text = try Self.render(compact: false)

        #expect(text.changes.isEmpty)
        #expect(text.rows.contains { $0.kind == .removed })
    }
}
