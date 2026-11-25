/// One row's text as a `String`, with the byte ↔ UTF-16 boundary maps a typesetting task needs to move between the
/// model's `ByteOffset`s and CoreText's UTF-16 string indices (text-renderer.md §3.2, §3.9).
struct RowText {
    let string: String
    /// The UTF-16 offset at every byte offset, `byteCount + 1` entries; only scalar-boundary offsets are ever queried.
    private let byteToUTF16: [Int32]
    /// The byte offset at every UTF-16 boundary, `utf16Count + 1` entries.
    private let utf16ToByte: [Int32]

    init(bytes: ArraySlice<UInt8>) {
        string = String(decoding: bytes, as: UTF8.self)
        var byteToUTF16 = [Int32](repeating: 0, count: bytes.count + 1)
        var utf16ToByte: [Int32] = []
        utf16ToByte.reserveCapacity(bytes.count + 1)
        var byteOffset = 0
        var utf16Offset: Int32 = 0
        for scalar in string.unicodeScalars {
            let utf16Length = scalar.value > 0xFFFF ? 2 : 1
            let byteLength = UTF8.width(scalar)
            for offset in 0 ..< byteLength where byteOffset + offset < byteToUTF16.count {
                byteToUTF16[byteOffset + offset] = utf16Offset
            }
            for _ in 0 ..< utf16Length { utf16ToByte.append(Int32(byteOffset)) }
            byteOffset += byteLength
            utf16Offset += Int32(utf16Length)
        }
        if byteOffset < byteToUTF16.count { byteToUTF16[byteOffset] = utf16Offset }
        utf16ToByte.append(Int32(byteOffset))
        self.byteToUTF16 = byteToUTF16
        self.utf16ToByte = utf16ToByte
    }

    /// The UTF-16 offset of the byte offset `byte`, which must fall on a scalar boundary.
    func utf16Offset(atByte byte: Int) -> Int {
        guard byte >= 0 else { return 0 }
        guard byte < byteToUTF16.count else { return Int(byteToUTF16.last ?? 0) }
        return Int(byteToUTF16[byte])
    }

    /// The byte offset of the UTF-16 boundary `index`.
    func byteOffset(atUTF16 index: Int) -> Int {
        guard index >= 0 else { return 0 }
        guard index < utf16ToByte.count else { return Int(utf16ToByte.last ?? 0) }
        return Int(utf16ToByte[index])
    }

    var utf16Count: Int { utf16ToByte.count - 1 }
}
