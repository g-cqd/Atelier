/// A font, described without touching CoreText, so it stays `Sendable` and crosses into a typesetting task cheaply
/// (text-renderer.md §3.4, §3.7): a task builds its own `CTFont` from one of these and lets it go.
public struct FontSpec: Hashable, Sendable {
    /// `nil` uses the system monospaced face.
    public var postScriptName: String?
    public var pointSize: Double
    public var features: [FontFeature]
    public var variations: [FontVariation]
    /// Prepended to the font's default cascade list.
    public var fallback: [String]

    public init(
        postScriptName: String? = nil, pointSize: Double, features: [FontFeature] = [],
        variations: [FontVariation] = [], fallback: [String] = []
    ) {
        self.postScriptName = postScriptName
        self.pointSize = pointSize
        self.features = features
        self.variations = variations
        self.fallback = fallback
    }

    /// This spec at `pointSize`, everything else unchanged: how a zoom command or a size-dependent layout resizes it.
    public func with(pointSize: Double) -> FontSpec {
        var copy = self
        copy.pointSize = pointSize
        return copy
    }
}

/// An OpenType feature tag and value, e.g. `("liga", 1)`.
public struct FontFeature: Hashable, Sendable {
    public var tag: String
    public var value: Int

    public init(tag: String, value: Int) {
        self.tag = tag
        self.value = value
    }
}

/// A variable font axis tag and value, e.g. `("wght", 500)`.
public struct FontVariation: Hashable, Sendable {
    public var axis: String
    public var value: Double

    public init(axis: String, value: Double) {
        self.axis = axis
        self.value = value
    }
}

/// The appearance a tile is rendered for; resolves ``ColorRef/adaptive(light:dark:highContrast:)``.
public enum Appearance: Hashable, Sendable {
    case light
    case dark
}
