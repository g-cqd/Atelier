public struct SearchQuery: Sendable, Equatable {
    public var text: String
    public var isCaseSensitive: Bool
    public var isRegex: Bool

    public init(text: String, isCaseSensitive: Bool = false, isRegex: Bool = false) {
        self.text = text
        self.isCaseSensitive = isCaseSensitive
        self.isRegex = isRegex
    }
}
