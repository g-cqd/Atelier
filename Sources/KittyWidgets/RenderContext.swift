import KittyCodecs

/// Accumulated style context passed down the view tree during rendering.
/// Modifiers push style overrides onto this context.
public struct RenderContext: Sendable {
    public var foreground: Color?
    public var background: Color?
    public var bold: Bool?
    public var italic: Bool?

    public var isFocused: Bool?

    public var focusMap: FocusMapCollector?

    public var environmentValues: EnvironmentValues = EnvironmentValues()

    private var _values: [ObjectIdentifier: any Sendable] = [:]

    public init() {}

    public mutating func set<T: Sendable>(_ type: T.Type, value: T) {
        _values[ObjectIdentifier(type)] = value
    }

    public func get<T: Sendable>(_ type: T.Type) -> T? {
        _values[ObjectIdentifier(type)] as? T
    }

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
        if let f = other.isFocused { result.isFocused = f }
        if let fm = other.focusMap { result.focusMap = fm }
        result.environmentValues = self.environmentValues.merging(other.environmentValues)
        for (key, val) in other._values {
            result._values[key] = val
        }
        return result
    }
}
