import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct CellTests {
    @Test
    func `Default cell is space with default style`() {
        let cell = Cell.empty
        #expect(cell.character == " ")
        #expect(cell.style == .default)
        #expect(cell.width == 1)
    }
}
