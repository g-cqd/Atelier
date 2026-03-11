import Foundation

public struct SymbolRecord: Sendable, Codable, Equatable {
    public enum Visibility: String, Sendable, Codable, CaseIterable {
        case publicSymbol
        case privateSymbol
    }

    public let name: String
    public let visibility: Visibility
    public let assetGlyphIndex: Int?
    public let codepoint: UInt32?
    public let glyph: String?
    public let availability: String?
    public let categories: [String]
    public let searchTerms: [String]

    public init(
        name: String,
        visibility: Visibility,
        assetGlyphIndex: Int?,
        codepoint: UInt32?,
        glyph: String?,
        availability: String?,
        categories: [String],
        searchTerms: [String]
    ) {
        self.name = name
        self.visibility = visibility
        self.assetGlyphIndex = assetGlyphIndex
        self.codepoint = codepoint
        self.glyph = glyph
        self.availability = availability
        self.categories = categories
        self.searchTerms = searchTerms
    }
}

extension SymbolRecord {
    var mappingEntry: SymbolMappingEntry {
        SymbolMappingEntry(name: name, visibility: visibility, assetGlyphIndex: assetGlyphIndex, codepoint: codepoint)
    }
}
