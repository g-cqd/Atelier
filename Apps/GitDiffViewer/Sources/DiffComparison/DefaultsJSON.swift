import AemiJSON
import Foundation

/// JSON coding, through AemiJSON, for the values ``ViewerSettings`` and ``RecentComparisons`` keep as `Data` in user
/// defaults. AemiJSON codes a `URL` through its keyed `Codable` form where Foundation's coders use a plain string, so a
/// value stored here holds no `URL`.
enum DefaultsJSON {
    /// The deepest nesting a stored value may have. Stored values nest a few levels; the bound keeps the recursive
    /// decode far from what a 512 KiB cooperative-pool stack survives.
    static let maxDepth = 64

    /// - Throws: `JSONError` when `data` is not JSON or nests deeper than ``maxDepth``; `DecodingError` when it does
    ///   not hold a `Value`.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        var decoder = AemiJSON.JSONDecoder()
        decoder.maxDecodingDepth = maxDepth
        decoder.options.maxDepth = maxDepth
        return try decoder.decode(type, from: data)
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try AemiJSON.JSONEncoder().encode(value)
    }
}
