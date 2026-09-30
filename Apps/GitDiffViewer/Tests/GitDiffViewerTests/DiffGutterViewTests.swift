import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

@MainActor
@Suite(.mainActorLane)
struct DiffGutterViewTests {
    private func text(lines: Int) -> String {
        (1 ... lines).map { "let value\($0) = \($0)\n" }.joined()
    }

    /// An embedded gutter, showing its whole document, over a fully laid-out text of `lines` rows. The gutter holds
    /// its layout weakly, so the caller keeps it.
    private func makeSUT(lines: Int) throws -> (gutter: DiffGutterView, layout: StaticTextLayout) {
        let source = text(lines: lines)
        let rendered = try #require(DiffRenderer.render(oldText: source, newText: source, language: .plain).new)
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 800)
        let sut = DiffGutterView(clipView: nil)
        sut.style = .new
        sut.source = layout
        sut.rendered = rendered
        sut.frame = NSRect(x: 0, y: 0, width: sut.thickness, height: layout.height)
        return (sut, layout)
    }

    @Test
    func `a band of a tall embedded gutter visits only the rows inside it, in order`() throws {
        let (sut, layout) = try makeSUT(lines: 400)
        defer { withExtendedLifetime(layout) {} }
        let band = NSRect(x: 0, y: sut.bounds.midY, width: sut.bounds.width, height: 100)
        var visited: [(row: Int, y: CGFloat, height: CGFloat)] = []
        sut.forEachRow(in: band) { frame, _, row, y, _ in
            visited.append((row, y, frame.height))
        }
        let rows = visited.map(\.row)
        #expect(!visited.isEmpty)
        #expect(visited.allSatisfy { $0.y <= band.maxY && $0.y + $0.height >= band.minY })
        #expect(rows == Array((rows.first ?? 0) ..< (rows.first ?? 0) + rows.count))
        #expect((rows.first ?? 0) > 0)
    }

    @Test
    func `a band below the last row visits nothing`() throws {
        let (sut, layout) = try makeSUT(lines: 40)
        defer { withExtendedLifetime(layout) {} }
        var visited = 0
        sut.forEachRow(in: NSRect(x: 0, y: sut.bounds.maxY + 50, width: 10, height: 100)) { _, _, _, _, _ in
            visited += 1
        }
        #expect(visited == 0)
    }

    @Test
    func `the number column widens with the widest line number and follows a new text`() throws {
        let (twoDigits, _) = try makeSUT(lines: 99)
        let (threeDigits, _) = try makeSUT(lines: 100)
        #expect(threeDigits.thickness > twoDigits.thickness)
        threeDigits.rendered = twoDigits.rendered
        #expect(threeDigits.thickness == twoDigits.thickness)
    }

    @Test
    func `a gutter with no text yet already reserves two digits`() throws {
        let sut = DiffGutterView(clipView: nil)
        sut.style = .new
        #expect(sut.thickness == (try makeSUT(lines: 12)).gutter.thickness)
    }
}
