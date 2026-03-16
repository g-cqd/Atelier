import KittyCodecs

public struct Separator: View, Sendable {
    public let character: Character
    public let style: Style
    public let axis: Axis

    public init(
        character: Character = "\u{2502}",
        style: Style = .default,
        axis: Axis = .vertical
    ) {
        self.character = character
        self.style = style
        self.axis = axis
    }

    public var body: Never { fatalError() }
}
