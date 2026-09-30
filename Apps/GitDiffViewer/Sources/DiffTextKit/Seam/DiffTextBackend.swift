package import CoreGraphics
package import DiffRendering

/// A card's text: sized for SwiftUI first, shown afterwards without measuring again (text-renderer.md §4.1).
///
/// A card's pane does not come from here yet: it keeps its own view until the cards route through the backend, with
/// the card layout work (§4.5, commit 8).
@MainActor
package protocol DiffCardText: AnyObject {
    /// The card's text size in a pane `width` wide, lines broken by `mode`.
    /// - Complexity: O(1) without wrapping; with wrapping, O(rows) for TextKit, and O(rows) without typesetting for
    ///   CoreText (an estimate, corrected as rows are typeset).
    func size(forWidth width: CGFloat, mode: WrapMode) -> CGSize
}

/// A text engine: it makes the panes and the card texts of a window (text-renderer.md §4.1).
@MainActor
package protocol DiffTextBackend {
    var kind: TextBackendKind { get }
    func makePane(gutter: GutterStyle) -> any DiffTextPane
    func makeCardText(for rendered: RenderedText) -> any DiffCardText
}
