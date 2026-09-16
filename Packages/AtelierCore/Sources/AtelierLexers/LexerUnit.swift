/// A code unit the scanners run over: UTF-8 bytes for a byte rope, UTF-16 units for a TextKit store. Every
/// pattern the scanners match is ASCII, so a unit above 127 is identifier text in both encodings and the token
/// boundaries come out on the same characters.
protocol LexerUnit: FixedWidthInteger, UnsignedInteger {
    associatedtype Codec: Unicode.Encoding where Codec.CodeUnit == Self
}

extension UInt8: LexerUnit {
    typealias Codec = UTF8
}

extension UInt16: LexerUnit {
    typealias Codec = UTF16
}

extension LexerUnit {
    /// The text of a run of units, for keyword and tag lookups.
    static func text(_ units: some Collection<Self>) -> String {
        String(decoding: units, as: Codec.self)
    }
}

extension Set<UInt8> {
    /// Whether the set holds `unit`, false for any unit outside the byte range.
    func contains<Unit: BinaryInteger>(unit: Unit) -> Bool {
        guard let byte = UInt8(exactly: unit) else { return false }
        return contains(byte)
    }
}
