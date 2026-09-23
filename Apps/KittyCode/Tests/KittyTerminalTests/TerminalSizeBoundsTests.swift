import Testing

@testable import KittyTerminal

/// A terminal may report any window size: the app must neither allocate cells for an absurd grid nor divide by, or
/// transmit images at, an absurd cell size.
@Suite
struct TerminalSizeBoundsTests {
    @Test(arguments: [
        TerminalSize(columns: 80, rows: 24, pixelWidth: 640, pixelHeight: 23),
        TerminalSize(columns: 80, rows: 24, pixelWidth: 79, pixelHeight: 480),
        TerminalSize(columns: 1, rows: 1, pixelWidth: 257, pixelHeight: 20),
        TerminalSize(columns: 1, rows: 1, pixelWidth: 10, pixelHeight: 513),
        TerminalSize(columns: 2, rows: 1, pixelWidth: 65_535, pixelHeight: 65_535),
        TerminalSize(columns: 80, rows: 24, pixelWidth: -640, pixelHeight: 480)
    ])
    func `a cell size outside 1 to 256 by 1 to 512 pixels is no cell size`(size: TerminalSize) {
        #expect(TerminalCapabilities.cellPixelSize(of: size) == nil)
    }

    @Test(arguments: [(1, 1), (256, 512)])
    func `the smallest and largest drawable cell sizes are kept`(width: Int, height: Int) {
        let size = TerminalSize(columns: 3, rows: 2, pixelWidth: width * 3, pixelHeight: height * 2)
        #expect(TerminalCapabilities.cellPixelSize(of: size) == .init(width: width, height: height))
    }

    @Test
    func `the largest size a terminal can report is limited to 1,024 by 512 cells`() {
        let size = TerminalSize(columns: 65_535, rows: 65_535, pixelWidth: 65_535, pixelHeight: 65_535)
        #expect(
            TerminalCapabilities.clampedSize(size)
                == TerminalSize(columns: 1_024, rows: 512, pixelWidth: 1_024, pixelHeight: 512))
    }

    @Test
    func `a limited size keeps the cell size of the reported one`() {
        let size = TerminalSize(columns: 4_000, rows: 2_000, pixelWidth: 32_003, pixelHeight: 32_005)
        let clamped = TerminalCapabilities.clampedSize(size)
        #expect(clamped.columns == 1_024 && clamped.rows == 512)
        #expect(TerminalCapabilities.cellPixelSize(of: clamped) == .init(width: 8, height: 16))
    }

    @Test(arguments: [
        TerminalSize(columns: 80, rows: 24),
        TerminalSize(columns: 1_024, rows: 512, pixelWidth: 8_192, pixelHeight: 8_192),
        TerminalSize(columns: 1, rows: 1, pixelWidth: 9, pixelHeight: 17)
    ])
    func `a size within the limits is unchanged`(size: TerminalSize) {
        #expect(TerminalCapabilities.clampedSize(size) == size)
    }

    @Test
    func `a negative count becomes zero`() {
        let clamped = TerminalCapabilities.clampedSize(TerminalSize(columns: -3, rows: -1))
        #expect(clamped == TerminalSize(columns: 0, rows: 0))
    }
}
