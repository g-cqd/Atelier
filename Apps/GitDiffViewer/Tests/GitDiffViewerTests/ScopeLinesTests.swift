import AtelierSwiftSyntax
import DiffCore
import Testing

@testable import DiffRendering

/// A side's scopes by source line, as the ribbon reads them (DIFF-03).
struct ScopeLinesTests {
    static let text = "struct S {\n    func f() {\n        let a = 1\n    }\n    var v: Int { 1 }\n}\n"

    static func scopes() throws -> ScopeLines {
        let facts = try #require(SwiftSyntaxFacts.extract(text))
        return ScopeLines(
            facts.scopes, text: text, lineRanges: DiffRenderer.lineRanges(of: text, lines: DiffModel.lines(of: text)))
    }

    @Test
    func `each line knows its depth, its innermost scope and where a scope ends, one-line braces left out`() throws {
        let sut = try Self.scopes()

        #expect(sut.scopes.map(\.lines) == [0 ... 5, 1 ... 3])
        #expect(sut.scopes.map(\.depth) == [1, 2])
        #expect(sut.scopes.map(\.kind) == [.type, .function])
        #expect(sut.scopes[1].openColumn == 13)
        #expect(sut.scopes[1].closeColumn == 4)
        #expect((0 ... 6).map(sut.depth(ofLine:)) == [1, 2, 2, 2, 1, 1, 0])
        #expect((0 ... 6).map(sut.innermostScope(atLine:)) == [0, 1, 1, 1, 0, 0, nil])
        #expect((0 ... 6).filter(sut.endsScope(atLine:)) == [3, 5])
    }

    @Test
    func `a source line is found among rows that skip it on the other side`() {
        let rendered = DiffRenderer.render(oldText: "a\nb\nc\n", newText: "a\nc\nd\n", language: .plain)
        guard let unified = rendered.unified else {
            Issue.record("no unified text")
            return
        }

        let rows = (0 ..< 3).map { unified.rowIndex(ofLine: $0, old: false) }

        #expect(rows.allSatisfy { $0 != nil })
        #expect(rows.compactMap(\.self).map { unified.rows[$0].newNumber } == [1, 2, 3])
        #expect(unified.rowIndex(ofLine: 1, old: true).map { unified.rows[$0].oldNumber } == 2)
        #expect(unified.rowIndex(ofLine: 7, old: false) == nil)
    }
}
