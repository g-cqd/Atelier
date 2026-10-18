import Testing

@testable import KittySyntax
@testable import KittyWidgets
@testable import TerminalKitCodecs
@testable import TerminalKitRender

func makeTextRenderingBuffer(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
    ScreenBuffer(columns: columns, rows: rows)
}
