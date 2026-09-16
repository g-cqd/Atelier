public import Foundation

public struct SymbolCollection: Sendable, Codable, Equatable {
    public let generatedAt: Date
    public let records: [SymbolRecord]

    public init(generatedAt: Date = Date(), records: [SymbolRecord]) {
        self.generatedAt = generatedAt
        self.records = records
    }

    public var mappings: [SymbolMappingEntry] {
        records.map(\.mappingEntry)
    }
}
