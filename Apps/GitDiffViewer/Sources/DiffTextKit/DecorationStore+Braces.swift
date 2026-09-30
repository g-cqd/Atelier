import AppKit
import DiffRendering

/// The braces of the scope under the pointer, lit in the accent colour (DIFF-03): a rendering attribute over each brace,
/// which lays nothing out again, painted after the row's colour whenever TextKit validates the row.
extension DecorationStore {
    /// Lights the braces at `offsets`, UTF-16 offsets of the text on show, and puts out those lit before, which take
    /// their colour back.
    /// - Complexity: O(braces), plus validating the rows that hold them.
    package func highlightBraces(at offsets: [Int]) {
        guard offsets != litBraces else { return }
        let before = litBraces
        litBraces = offsets
        guard let layoutManager, let contentManager = layoutManager.textContentManager else { return }
        for offset in Set(before + offsets) {
            guard
                let location = contentManager.location(layoutManager.documentRange.location, offsetBy: offset),
                let end = contentManager.location(location, offsetBy: 1),
                let range = NSTextRange(location: location, end: end)
            else { continue }
            layoutManager.removeRenderingAttribute(.foregroundColor, for: range)
            // The row's colour comes back from its tokens, and the brace's light from ``litBraces``.
            if let fragment = layoutManager.textLayoutFragment(for: location) { validate(fragment, in: layoutManager) }
        }
    }

    /// Lights the braces lying in `span`, the UTF-16 offsets of a fragment being validated that starts at `anchor`.
    func paintLitBraces(
        in span: Range<Int>, anchor: (location: any NSTextLocation, offset: Int), layoutManager: NSTextLayoutManager
    ) {
        guard let contentManager = layoutManager.textContentManager else { return }
        for offset in litBraces where span.contains(offset) {
            guard let location = contentManager.location(anchor.location, offsetBy: offset - anchor.offset),
                let end = contentManager.location(location, offsetBy: 1),
                let range = NSTextRange(location: location, end: end)
            else { continue }
            layoutManager.setRenderingAttributes([.foregroundColor: NSColor.controlAccentColor], for: range)
        }
    }
}
