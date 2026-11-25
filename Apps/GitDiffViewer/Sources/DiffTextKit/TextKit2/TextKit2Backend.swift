package import CoreGraphics
package import DiffRendering
import Foundation

/// Today's TextKit 2 panes behind the seam (text-renderer.md §4.2): the text view, gutter and minimap of
/// ``TextKit2Pane``, and the detached layout of ``StaticTextLayout`` for a card.
@MainActor
package struct TextKit2Backend: DiffTextBackend {
    package init() {}

    package var kind: TextBackendKind { .textKit2 }

    package func makePane(gutter: GutterStyle) -> any DiffTextPane {
        let pane = TextKit2Pane(options: TextKit2Pane.Options(gutter: gutter), coordinator: DiffTextViewCoordinator())
        pane.installDecorations()
        return pane
    }

    package func makeCardText(for rendered: RenderedText) -> any DiffCardText {
        TextKit2CardText(layout: StaticTextLayout(rendered: rendered))
    }
}

/// A card's text measured by its detached TextKit 2 layout.
@MainActor
package final class TextKit2CardText: DiffCardText {
    package let layout: StaticTextLayout

    package init(layout: StaticTextLayout) {
        self.layout = layout
    }

    package func size(forWidth width: CGFloat, mode: WrapMode) -> CGSize {
        layout.layOut(mode: mode, viewportWidth: width)
        return CGSize(width: layout.contentWidth, height: layout.height)
    }
}
