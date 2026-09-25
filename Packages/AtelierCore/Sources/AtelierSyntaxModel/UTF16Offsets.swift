/// Ascending UTF-8 byte offsets moved to UTF-16 offsets in one forward walk over the bytes, for tokens a scanner found
/// in bytes and a caller places in a `String`'s UTF-16 view or a TextKit store.
public enum UTF16Offsets {
    /// Moves `byte` forward to `end`, adding to `unit` the UTF-16 units of the characters it passes: one for a lead
    /// byte, two for the lead of a four-byte character, none for a continuation byte.
    /// - Complexity: O(`end` - `byte`)
    @inlinable
    public static func advance(_ byte: inout Int, to end: Int, in bytes: Span<UInt8>, counting unit: inout Int) {
        while byte < end {
            let value = bytes[byte]
            unit += (value & 0xC0 == 0x80 ? 0 : 1) + (value >= 0xF0 ? 1 : 0)
            byte += 1
        }
    }
}
