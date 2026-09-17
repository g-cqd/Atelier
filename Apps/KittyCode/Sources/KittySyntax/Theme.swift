import AtelierSyntaxModel
public import AtelierTheme
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

    /// The terminal rendering of a shared theme: every role the theme styles becomes a capture-name entry, so
    /// the hierarchical fallback of ``style(for:)`` mirrors the role hierarchy, and the plain text becomes the
    /// default style.
    public init(_ theme: SyntaxTheme) {
        var styles: [String: Style] = [:]
        for (role, style) in theme.roles {
            styles[role.captureName] = Style(style)
        }
        self.init(styles: styles, defaultStyle: Style(theme.plainText))
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

    /// The shared Monokai palette, resolved to terminal styles.
    public static let monokai = Theme(.monokai)
}
