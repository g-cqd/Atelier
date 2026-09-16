import Testing

@testable import KittyTerminal

@Suite
struct TerminalTypesTests {
    @Test
    func `TerminalSize equality`() {
        let a = TerminalSize(columns: 80, rows: 24)
        let b = TerminalSize(columns: 80, rows: 24)
        #expect(a == b)
    }

    @Test
    func `TerminalSize with pixel dimensions`() {
        let size = TerminalSize(columns: 120, rows: 40, pixelWidth: 1920, pixelHeight: 1080)
        #expect(size.columns == 120)
        #expect(size.pixelWidth == 1920)
    }
}
