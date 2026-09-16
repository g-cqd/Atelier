public import KittyCodecs

public struct CenteredText: View, Sendable {
    public var text: String
    public var style: Style
    public var backgroundStyle: Style

    public init(text: String, style: Style = .default, backgroundStyle: Style = .default) {
        self.text = text
        self.style = style
        self.backgroundStyle = backgroundStyle
    }

    public var body: Never { fatalError() }
}
