import Foundation

public struct SymbolMappingEntry: Sendable, Codable, Equatable {
    public let name: String
    public let visibility: SymbolRecord.Visibility
    public let assetGlyphIndex: Int?
    public let codepoint: UInt32?

    public init(
        name: String, visibility: SymbolRecord.Visibility, assetGlyphIndex: Int?, codepoint: UInt32?
    ) {
        self.name = name
        self.visibility = visibility
        self.assetGlyphIndex = assetGlyphIndex
        self.codepoint = codepoint
    }

    public var glyph: String? {
        guard let codepoint, let scalar = UnicodeScalar(codepoint) else {
            return nil
        }
        return String(Character(scalar))
    }
}
