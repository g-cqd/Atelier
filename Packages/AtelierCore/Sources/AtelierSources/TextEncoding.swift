import Foundation

/// The encodings a file's text is read in besides UTF-8.
enum TextEncoding {
    /// The UTF-16 or UTF-32 encoding a byte-order mark at the start of `data` names; nil without one. UTF-32's
    /// little-endian mark starts with UTF-16's, so it is tested first.
    static func wideUnicode(of data: Data) -> String.Encoding? {
        let head = [UInt8](data.prefix(4))
        if head.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || head.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return .utf32 }
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return .utf16 }
        return nil
    }
}
