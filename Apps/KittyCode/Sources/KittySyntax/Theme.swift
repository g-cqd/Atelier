public import KittyStyle

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

    public static let monokai = Theme(
        styles: [
            // Keywords
            "keyword": Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true),

            // Functions
            "function": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "function.name": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "function.call": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "function.method": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "function.builtin": Style(fg: .rgb(r: 102, g: 217, b: 239)),
            "function.macro": Style(fg: .rgb(r: 166, g: 226, b: 46), bold: true),
            "function.special": Style(fg: .rgb(r: 166, g: 226, b: 46), italic: true),

            // Types
            "type": Style(fg: .rgb(r: 102, g: 217, b: 239), italic: true),
            "type.builtin": Style(fg: .rgb(r: 102, g: 217, b: 239), italic: true),

            // Strings
            "string": Style(fg: .rgb(r: 230, g: 219, b: 116)),
            "string.special": Style(fg: .rgb(r: 230, g: 219, b: 116)),
            "string.escape": Style(fg: .rgb(r: 174, g: 129, b: 255)),

            // Numbers
            "number": Style(fg: .rgb(r: 174, g: 129, b: 255)),
            "number.float": Style(fg: .rgb(r: 174, g: 129, b: 255)),

            // Comments
            "comment": Style(fg: .rgb(r: 117, g: 113, b: 94), italic: true),
            "comment.documentation": Style(fg: .rgb(r: 117, g: 113, b: 94), italic: true, underline: .single),

            // Variables
            "variable": Style(fg: .rgb(r: 248, g: 248, b: 242)),
            "variable.builtin": Style(fg: .rgb(r: 174, g: 129, b: 255), italic: true),
            "variable.parameter": Style(fg: .rgb(r: 253, g: 151, b: 31), italic: true),

            // Constants
            "constant": Style(fg: .rgb(r: 174, g: 129, b: 255)),
            "constant.builtin": Style(fg: .rgb(r: 174, g: 129, b: 255)),
            "boolean": Style(fg: .rgb(r: 174, g: 129, b: 255)),

            // Operators and punctuation
            "operator": Style(fg: .rgb(r: 249, g: 38, b: 114)),
            "punctuation": Style(fg: .rgb(r: 248, g: 248, b: 242)),
            "punctuation.bracket": Style(fg: .rgb(r: 248, g: 248, b: 242)),
            "punctuation.delimiter": Style(fg: .rgb(r: 248, g: 248, b: 242)),
            "punctuation.special": Style(fg: .rgb(r: 249, g: 38, b: 114)),

            // Other
            "property": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "tag": Style(fg: .rgb(r: 249, g: 38, b: 114)),
            "attribute": Style(fg: .rgb(r: 166, g: 226, b: 46)),
            "namespace": Style(fg: .rgb(r: 102, g: 217, b: 239)),
            "label": Style(fg: .rgb(r: 230, g: 219, b: 116)),
            "constructor": Style(fg: .rgb(r: 102, g: 217, b: 239)),
            "embedded": Style(fg: .rgb(r: 248, g: 248, b: 242)),
            "escape": Style(fg: .rgb(r: 174, g: 129, b: 255))
        ], defaultStyle: Style(fg: .rgb(r: 248, g: 248, b: 242)))
}
