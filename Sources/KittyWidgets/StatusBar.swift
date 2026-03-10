import KittyCodecs

/// Status bar with left/center/right aligned segments.
public struct StatusBar: View, Sendable {
    public var left: String
    public var center: String
    public var right: String
    public var style: Style

    public init(
        left: String = "",
        center: String = "",
        right: String = "",
        style: Style = Style(fg: .rgb(r: 0, g: 0, b: 0), bg: .rgb(r: 200, g: 200, b: 200))
    ) {
        self.left = left
        self.center = center
        self.right = right
        self.style = style
    }

    public var body: Never { fatalError() }

    /// Render the status bar into a fixed-width string.
    public func render(width: Int) -> String {
        guard width > 0 else { return "" }
        let leftPart = left.prefix(width / 3)
        let rightPart = right.suffix(width / 3)
        let centerSpace = width - leftPart.count - rightPart.count
        let centerPart = center.prefix(centerSpace)
        let padding = centerSpace - centerPart.count
        let leftPadding = padding / 2
        let rightPadding = padding - leftPadding

        return String(leftPart)
            + String(repeating: " ", count: leftPadding)
            + String(centerPart)
            + String(repeating: " ", count: rightPadding)
            + String(rightPart)
    }
}
