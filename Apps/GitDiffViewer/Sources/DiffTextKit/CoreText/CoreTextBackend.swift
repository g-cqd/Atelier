package import DiffRendering
import Foundation

/// The CoreText renderer behind `DiffTextBackend` (text-renderer.md §4.2): draws a pane's rows and decorations
/// through `TextTypesetter` tiles. Drawing only in M1 (§5): no selection, hover, split alignment, and cards keep
/// their TextKit 2 layout (`StaticTextLayout`) until a later hand-back routes them through the seam too.
@MainActor
package struct CoreTextBackend: DiffTextBackend {
    package init() {}

    package var kind: TextBackendKind { .coreText }

    package func makePane(gutter: GutterStyle) -> any DiffTextPane {
        CoreTextPane(gutter: gutter)
    }

    package func makeCardText(for rendered: RenderedText) -> any DiffCardText {
        TextKit2CardText(layout: StaticTextLayout(rendered: rendered))
    }
}
