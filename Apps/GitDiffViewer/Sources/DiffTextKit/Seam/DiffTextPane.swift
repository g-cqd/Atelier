package import AppKit
package import DiffRendering

/// One pane's text, whichever engine draws it (text-renderer.md §4.1). The comments name the rows of the parity
/// checklist (§1.2) each member serves.
@MainActor
package protocol DiffTextPane: AnyObject {
    /// The view the pane embeds: the scrolling pane with its gutter and minimap.
    var view: NSView { get }
    var clipView: NSClipView? { get }

    /// Shows `rendered`, at the top of the text or where the pane was when `keepingScroll` (rows 1-3, 15, 16, 21, 29).
    func show(_ rendered: RenderedText, keepingScroll: Bool)
    /// Draws `decorations` over the text on show, without laying it out again (rows 11-13).
    func setDecorations(_ decorations: DiffDecorations?)
    /// Breaks lines as `mode` says (rows 5-7).
    func setWrapping(_ mode: WrapMode)

    /// Where the rows lie (rows 4, 8, 10, 17, 18).
    var geometry: any DiffRowGeometry { get }
    /// Brings `row` into view once the pane has laid out what it shows: near the top, or centred (row 20).
    func scroll(toRow row: Int, centered: Bool)

    /// Heights of the rows' lines for split alignment, without their spacing; `isExact` is false while an engine
    /// still estimates wrapped rows (row 9).
    func rowHeights() -> (heights: [Double], isExact: Bool)
    /// Sets the spacing after each row, zero past the end of `spacing` (row 9).
    func setRowSpacing(_ spacing: [Double])

    /// The identifier under `point`, in the text view's coordinates (row 19).
    func hoverHit(at point: NSPoint) -> HoverHit?
    /// Where `hit`'s identifier lies now, in the text view's coordinates; nil once it no longer shows (row 19).
    func anchorRect(for hit: HoverHit) -> NSRect?
    // Selection, copy, find and accessibility (23-26) live inside `view`; the seam does not expose them.
}
