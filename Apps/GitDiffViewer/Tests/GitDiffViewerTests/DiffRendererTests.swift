import AemiRuntime
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
        let rows = try #require(rendered.unified?.rows)
        let kinds = rows.map(\.kind)
        #expect(kinds.first == .gap)
        #expect(rows.first?.gap?.hiddenRows == 7)
        #expect(kinds.filter { $0 == .gap }.count == 3)
        #expect(rows.last?.gap?.hiddenRows == 3)
        #expect(rendered.unifiedChangeStarts.count == 2)
        #expect(rows[1].oldNumber == 8)
    }

    @Test
    func `expanding a gap reveals its rows`() {
        let key = GapKey(fileIndex: 0, gapIndex: 0)
        let rendered = DiffRenderer.render(
            oldText: old, newText: new, language: .plain,
            layout: .changes(context: 2, expansions: [key: GapExpansion(below: 0, above: 4)])
        )
        #expect(rendered.unified?.rows.first?.gap?.hiddenRows == 3)
        #expect(rendered.unified?.rows[1].oldNumber == 4)
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
}
