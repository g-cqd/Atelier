import KittyCodecs

/// A single cell in the terminal screen buffer.
public struct Cell: Sendable, Equatable {
    public var character: Character
    public var style: Style
    public var width: UInt8

    public static let empty = Cell(character: " ", style: .default, width: 1)

    public init(character: Character = " ", style: Style = .default, width: UInt8 = 1) {
        self.character = character
        self.style = style
        self.width = width
    }
}
