import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

func makeTextRenderingBuffer(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
    ScreenBuffer(columns: columns, rows: rows)
}
