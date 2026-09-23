/// What the host terminal can do beyond cells, decided from its environment and the window geometry it reports.
public struct TerminalCapabilities: Sendable, Equatable {
    /// The size of one cell in pixels.
    public struct CellPixelSize: Sendable, Equatable {
        /// The cell widths, in pixels, that pixel chrome draws with.
        public static let drawableWidths = 1 ... 256
        /// The cell heights, in pixels, that pixel chrome draws with.
        public static let drawableHeights = 1 ... 512

        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        /// Whether the width is in ``drawableWidths`` and the height in ``drawableHeights``: a size that no pixel
        /// computation divides by zero and whose images stay small.
        public var isDrawable: Bool {
            Self.drawableWidths.contains(width) && Self.drawableHeights.contains(height)
        }
    }

    /// The most columns a screen gets cells for, whatever size the terminal reports.
    public static let maximumColumns = 1_024
    /// The most rows a screen gets cells for, whatever size the terminal reports.
    public static let maximumRows = 512

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

    /// The cell size a window size implies; nil when the terminal reports no pixel dimensions or the cell size is
    /// not ``CellPixelSize/isDrawable``.
    public static func cellPixelSize(of size: TerminalSize) -> CellPixelSize? {
        guard size.columns > 0, size.rows > 0 else { return nil }
        let cell = CellPixelSize(width: size.pixelWidth / size.columns, height: size.pixelHeight / size.rows)
        return cell.isDrawable ? cell : nil
    }

    /// `size` with its columns and rows limited to ``maximumColumns`` and ``maximumRows``, and negative counts made
    /// zero. The pixel dimensions shrink with a limited count so that ``cellPixelSize(of:)`` gives the same cell.
    public static func clampedSize(_ size: TerminalSize) -> TerminalSize {
        let (columns, pixelWidth) = clamped(count: size.columns, pixels: size.pixelWidth, maximum: maximumColumns)
        let (rows, pixelHeight) = clamped(count: size.rows, pixels: size.pixelHeight, maximum: maximumRows)
        return TerminalSize(columns: columns, rows: rows, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// `count` limited to `0 ... maximum`, and `pixels` rescaled to `maximum` cells of the original per-cell pixels
    /// when the limit applies; the product cannot overflow, since its magnitude stays below that of `pixels`.
    private static func clamped(count: Int, pixels: Int, maximum: Int) -> (count: Int, pixels: Int) {
        guard count > maximum else { return (max(0, count), pixels) }
        return (maximum, pixels / count * maximum)
    }
}
