/// A role-preserving intermediate representation for a highlighted region of source code.
/// Unlike `StyledSpan`, tokens carry semantic information (role, modifiers, layer)
/// and can be merged across multiple highlighting layers before style resolution.
public struct HighlightToken: Sendable, Equatable {
    public let byteRange: Range<Int>
    public let role: HighlightRole
    public let modifiers: HighlightModifierSet
    public let layer: HighlightLayer
    public let priority: Int

    public init(
        byteRange: Range<Int>,
        role: HighlightRole,
        modifiers: HighlightModifierSet = [],
        layer: HighlightLayer = .structural,
        priority: Int = 0
    ) {
        self.byteRange = byteRange
        self.role = role
        self.modifiers = modifiers
        self.layer = layer
        self.priority = priority
    }
}

/// The highlighting tier that produced a token.
/// Higher layers take precedence when tokens overlap.
public enum HighlightLayer: UInt8, Sendable, Comparable, Hashable {
    case lexical = 0
    case structural = 1
    case semantic = 2

    public static func < (lhs: HighlightLayer, rhs: HighlightLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
