/// A code unit the HTML and CSS scanners run over; they scan an owned copy of the bytes.
protocol LexerUnit: FixedWidthInteger, UnsignedInteger {
    associatedtype Codec: Unicode.Encoding where Codec.CodeUnit == Self
}

extension UInt8: LexerUnit {
    typealias Codec = UTF8
}

extension LexerUnit {
    /// The text of a run of units, for keyword and tag lookups.
    static func text(_ units: some Collection<Self>) -> String {
        String(decoding: units, as: Codec.self)
    }
}
