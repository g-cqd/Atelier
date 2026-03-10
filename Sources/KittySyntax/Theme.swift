import KittyCodecs

/// Maps capture names to visual styles with hierarchical fallback.
/// For example, `@keyword.function` falls back to `@keyword` if no specific mapping exists.
public struct Theme: Sendable {
    private var styles: [String: Style]
    public var defaultStyle: Style

    public init(styles: [String: Style] = [:], defaultStyle: Style = .default) {
        self.styles = styles
        self.defaultStyle = defaultStyle
    }

    /// Look up the style for a capture name with hierarchical fallback.
    public func style(for capture: String) -> Style {
        let name = capture.hasPrefix("@") ? String(capture.dropFirst()) : capture

        // Try exact match first
        if let style = styles[name] { return style }

        // Try hierarchical fallback: keyword.function → keyword
        var parts = name.split(separator: ".")
        while parts.count > 1 {
            parts.removeLast()
            let prefix = parts.joined(separator: ".")
            if let style = styles[prefix] { return style }
        }

        return defaultStyle
    }

    /// Set the style for a capture name.
    public mutating func setStyle(_ style: Style, for capture: String) {
        let name = capture.hasPrefix("@") ? String(capture.dropFirst()) : capture
        styles[name] = style
    }

    // MARK: - Built-in Themes

    public static let monokai = Theme(styles: [
        "keyword": Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true),
        "function": Style(fg: .rgb(r: 166, g: 226, b: 46)),
        "function.name": Style(fg: .rgb(r: 166, g: 226, b: 46)),
        "type": Style(fg: .rgb(r: 102, g: 217, b: 239), italic: true),
        "string": Style(fg: .rgb(r: 230, g: 219, b: 116)),
        "number": Style(fg: .rgb(r: 174, g: 129, b: 255)),
        "comment": Style(fg: .rgb(r: 117, g: 113, b: 94), italic: true),
        "variable": Style(fg: .rgb(r: 248, g: 248, b: 242)),
        "constant": Style(fg: .rgb(r: 174, g: 129, b: 255)),
        "operator": Style(fg: .rgb(r: 249, g: 38, b: 114)),
        "punctuation": Style(fg: .rgb(r: 248, g: 248, b: 242)),
        "property": Style(fg: .rgb(r: 166, g: 226, b: 46)),
        "tag": Style(fg: .rgb(r: 249, g: 38, b: 114)),
        "attribute": Style(fg: .rgb(r: 166, g: 226, b: 46)),
    ], defaultStyle: Style(fg: .rgb(r: 248, g: 248, b: 242)))
}
