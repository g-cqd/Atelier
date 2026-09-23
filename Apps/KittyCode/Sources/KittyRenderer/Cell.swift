import KittyCodecs
public import KittyStyle

/// A single cell in the terminal screen buffer.
public struct Cell: Sendable, Equatable {
    /// The Unicode character displayed in this cell.
    public var character: Character

    /// The visual style (foreground color, background color, attributes) applied to this cell.
    public var style: Style

    /// The number of terminal columns this cell occupies. Wide characters (e.g. CJK) use 2.
    public var width: UInt8

    /// A blank cell with a space character, default style, and single-column width.
    public static let empty = Cell(character: " ", style: .default, width: 1)

    /// The placeholder in the second column of a wide character, which the diff skips because the terminal fills
    /// that column itself.
    public static let continuation = Cell(character: "\0", style: .default, width: 0)

    /// Whether this cell is the trailing half of a wide character.
    public var isContinuation: Bool { width == 0 }

    /// Creates a cell with the given character, style, and column width.
    ///
    /// - Parameters:
    ///   - character: The Unicode character to display. Defaults to a space.
    ///   - style: The visual style to apply. Defaults to `.default`.
    ///   - width: The number of terminal columns the character occupies. Defaults to `1`.
    public init(character: Character = " ", style: Style = .default, width: UInt8 = 1) {
        self.character = character
        self.style = style
        self.width = width
    }
}
