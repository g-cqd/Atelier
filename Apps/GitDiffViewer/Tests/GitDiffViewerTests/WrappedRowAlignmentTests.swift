import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Side-by-side rows that wrap onto more lines on one side than on the other (book DIFF-06). The spacing that lines
/// them up changes TextKit's usage bounds from within TextKit's invalidation of that edit: a pane that sized itself
/// there read the layout TextKit was invalidating, which invalidated it again under the first invalidation, and that
/// one never ended. The main thread spun, and the window froze.
@MainActor
@Suite(.mainActorLane)
struct WrappedRowAlignmentTests {
    @Test
    func `rows that wrap onto more lines on one side line up with the other side's, and the panes keep running`()
        async throws
    {
        let sut = HostedPanes(showing: .wrappingOnOneSide(rows: 60), layout: .sideBySide, wrapsLines: true)

        try await withMainThreadBound("Aligning rows that wrap differently on each side") {
            try await sut.alignSides()
        }

        let panes = try sut.panes()
        let lineHeight = panes[0].lineHeight
        // The old side's rows wrap and the new side's do not: the new side's rows take the spacing.
        #expect(try panes[0].bottom(ofRow: 1) - panes[0].top(ofRow: 1) > 1.5 * lineHeight)
        #expect(abs(try panes[1].bottom(ofRow: 1) - panes[0].bottom(ofRow: 1)) < 0.5)
        for row in 1 ... 3 {
            #expect(abs(try panes[0].top(ofRow: row) - panes[1].top(ofRow: row)) < 0.5, "row \(row)")
        }
    }
}

extension PaneText {
    /// `rows` rows changed from old lines some 60 characters long, which wrap in a pane half the window wide, to new
    /// lines some 15 long, which do not.
    static func wrappingOnOneSide(rows: Int) -> PaneText {
        func line(_ name: String, _ index: Int, length: Int) -> String {
            let head = "let \(name)\(index) = "
            return head + String(repeating: "x", count: max(length - head.count, 1))
        }
        let old = (1 ... rows).map { line("old", $0, length: 60) }
        let new = (1 ... rows).map { line("new", $0, length: 15) }
        let rendered = DiffRenderer.render(
            oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n", language: .plain)
        return PaneText(rendered: rendered, asksForChange: false)
    }
}
