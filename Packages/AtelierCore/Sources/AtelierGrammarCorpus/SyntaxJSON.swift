import AemiJSON
import Foundation

/// AemiJSON set up for the JSON files the syntax tier reads and writes: the language manifests and the
/// compiled-table cache. Reads skip a leading UTF-8 byte-order mark, as Foundation's JSON readers do, and stop at
/// ``maxDepth``.
enum SyntaxJSON {
    /// The deepest nesting a file may have. A compiled table nests about seven levels and a manifest three; the bound
    /// keeps the recursive decode far from what a 512 KiB cooperative-pool stack survives.
    static let maxDepth = 64

    /// - Throws: `JSONError` when `data` is not JSON or nests deeper than ``maxDepth``.
    /// - Complexity: O(n) in the size of `data`.
    static func parse(_ data: Data) throws(JSONError) -> JSONDocument {
        try AemiJSON.parse(bytesSkippingByteOrderMark(data), options: JSONParseOptions(maxDepth: maxDepth))
    }

    /// - Throws: `JSONError` when `data` is not JSON or nests deeper than ``maxDepth``; `DecodingError` when it does
    ///   not hold a `Value`.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        var decoder = AemiJSON.JSONDecoder()
        decoder.maxDecodingDepth = maxDepth
        decoder.options.maxDepth = maxDepth
        return try decoder.decode(type, from: bytesSkippingByteOrderMark(data))
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try AemiJSON.JSONEncoder().encode(value)
    }

    private static func bytesSkippingByteOrderMark(_ data: Data) -> [UInt8] {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        return data.starts(with: byteOrderMark) ? Array(data.dropFirst(byteOrderMark.count)) : Array(data)
    }
}
