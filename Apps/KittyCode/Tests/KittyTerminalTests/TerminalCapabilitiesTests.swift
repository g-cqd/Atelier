import Testing

@testable import KittyTerminal

/// What the environment and the reported window size say about the terminal.
struct TerminalCapabilitiesTests {
    private let size = TerminalSize(columns: 100, rows: 40, pixelWidth: 1000, pixelHeight: 800)

    @Test(arguments: [
        (["KITTY_WINDOW_ID": "1"], true), (["TERM": "xterm-kitty"], true), (["TERM_PROGRAM": "ghostty"], true),
        (["TERM_PROGRAM": "WezTerm"], true), (["KONSOLE_VERSION": "230800"], true),
        (["TERM_PROGRAM": "Apple_Terminal", "TERM": "xterm-256color"], false), ([:], false)
    ])
    func `graphics support comes from the environment`(environment: [String: String], expected: Bool) {
        #expect(TerminalCapabilities(environment: environment, size: size).supportsKittyGraphics == expected)
    }

    @Test
    func `the cell size divides the window pixels by the cells and needs both`() {
        #expect(TerminalCapabilities.cellPixelSize(of: size) == .init(width: 10, height: 20))
        #expect(TerminalCapabilities.cellPixelSize(of: TerminalSize(columns: 100, rows: 40)) == nil)
        #expect(
            TerminalCapabilities.cellPixelSize(of: TerminalSize(columns: 0, rows: 40, pixelWidth: 1, pixelHeight: 1))
                == nil)
    }

    @Test
    func `pixel chrome needs graphics and a cell size`() {
        #expect(TerminalCapabilities(environment: ["KITTY_WINDOW_ID": "1"], size: size).supportsPixelChrome)
        #expect(
            !TerminalCapabilities(environment: ["KITTY_WINDOW_ID": "1"], size: TerminalSize(columns: 80, rows: 24))
                .supportsPixelChrome)
        #expect(!TerminalCapabilities(environment: [:], size: size).supportsPixelChrome)
    }
}
