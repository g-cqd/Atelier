/// What the host terminal can do beyond cells, decided from its environment and the window geometry it reports.
public struct TerminalCapabilities: Sendable, Equatable {
    /// The size of one cell in pixels.
    public struct CellPixelSize: Sendable, Equatable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Whether the terminal speaks the kitty graphics protocol. Decided from the environment: kitty
    /// (`KITTY_WINDOW_ID`, or `TERM` naming kitty), Ghostty and WezTerm (`TERM_PROGRAM`), and Konsole (`KONSOLE_VERSION`).
    public var supportsKittyGraphics: Bool
    /// The pixel size of a cell, from the window size the terminal reports; nil when it reports no pixels.
    public var cellPixelSize: CellPixelSize?

    public init(supportsKittyGraphics: Bool, cellPixelSize: CellPixelSize? = nil) {
        self.supportsKittyGraphics = supportsKittyGraphics
        self.cellPixelSize = cellPixelSize
    }

    /// The capabilities implied by `environment` and a reported `size`.
    public init(environment: [String: String], size: TerminalSize) {
        let program = environment["TERM_PROGRAM"]?.lowercased() ?? ""
        let term = environment["TERM"]?.lowercased() ?? ""
        let graphics =
            environment["KITTY_WINDOW_ID"] != nil || term.contains("kitty") || program == "ghostty"
            || program == "wezterm" || environment["KONSOLE_VERSION"] != nil
        self.init(supportsKittyGraphics: graphics, cellPixelSize: Self.cellPixelSize(of: size))
    }

    /// Whether pixel chrome (1px separators under the cells) can be drawn: graphics plus a known cell size.
    public var supportsPixelChrome: Bool {
        supportsKittyGraphics && cellPixelSize != nil
    }

    /// The cell size a window size implies, nil when the terminal reports no pixel dimensions.
    public static func cellPixelSize(of size: TerminalSize) -> CellPixelSize? {
        guard size.columns > 0, size.rows > 0, size.pixelWidth > 0, size.pixelHeight > 0 else { return nil }
        return CellPixelSize(width: size.pixelWidth / size.columns, height: size.pixelHeight / size.rows)
    }
}
