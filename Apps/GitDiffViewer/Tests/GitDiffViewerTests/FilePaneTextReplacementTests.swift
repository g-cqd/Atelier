import AppKit
import Testing

@testable import DiffTextKit

/// A file pane shows another file after TextKit laid out much of the one it showed, as it has once the first change
/// of a long file was near its end, or once the file was scrolled through.
@MainActor
struct FilePaneTextReplacementTests {
    /// Dropping the rows TextKit laid out sized the pane again for each of them, one call inside the other, which
    /// overflowed the stack past some 1,800 rows.
    @Test
    func `a pane that laid out a long file whole shows another`() throws {
        let sut = HostedPanes(showing: .lines(3_000), layout: .inline, wrapsLines: false)
        let pane = try #require(try sut.panes().first)
        let layoutManager = try #require(pane.textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        sut.show(.lines(12))

        let shown = try #require(try sut.panes().first)
        #expect(shown.textView.frame.height == shown.clip.bounds.height)
    }
}
