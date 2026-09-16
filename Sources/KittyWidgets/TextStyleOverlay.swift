public import KittyCodecs

public struct ColorOverlay: Sendable, Equatable {
    public var color: Color
    public var alpha: Double

    public init(color: Color, alpha: Double = 1) {
        self.color = color
        self.alpha = min(1, max(0, alpha))
    }
}

public struct TextStyleOverlay: Sendable, Equatable {
    public var foreground: ColorOverlay?
    public var background: ColorOverlay?

    public init(
        foreground: ColorOverlay? = nil,
        background: ColorOverlay? = nil
    ) {
        self.foreground = foreground
        self.background = background
    }

    public var isEmpty: Bool {
        foreground == nil && background == nil
    }
}
