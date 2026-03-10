import KittyCodecs

/// Accumulated style context passed down the view tree during rendering.
/// Modifiers push style overrides onto this context.
public struct RenderContext: Sendable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?

    public init() {}

    /// Apply context overrides to a base style.
    public func applyTo(_ style: Style) -> Style {
        var result = style
        if let fg = foreground { result.fg = fg }
        if let bg = background { result.bg = bg }
        if let b = bold { result.bold = b }
        if let i = italic { result.italic = i }
        return result
    }

    /// Merge another context on top (later context wins).
    public func merging(_ other: RenderContext) -> RenderContext {
        var result = self
        if let fg = other.foreground { result.foreground = fg }
        if let bg = other.background { result.background = bg }
        if let b = other.bold { result.bold = b }
        if let i = other.italic { result.italic = i }
        return result
    }
}
