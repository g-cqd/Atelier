import Foundation

/// The OSC 52 reply a terminal sends to ``KittySequences/requestClipboard``, and its parser.
public enum OSCClipboard: Sendable {
    /// One clipboard reply.
    public enum Reply: Sendable, Equatable {
        /// The clipboard's text, with any invalid UTF-8 replaced by U+FFFD.
        case text(String)
        /// No payload: the clipboard is empty, or the terminal declined the read, which kitty answers this way.
        case empty
        /// A payload that is not base64.
        case unreadable
    }

    /// Parses one complete `ESC ] 52 ; <selection> ; <base64> ST` sequence, BEL or `ESC \` terminated, as the input
    /// router hands over an OSC it does not decode itself. Anything else is nil.
    public static func parse(_ bytes: [UInt8]) -> Reply? {
        let introducer: [UInt8] = [0x1b, 0x5d, 0x35, 0x32, 0x3b]  // ESC ] 5 2 ;
        guard bytes.starts(with: introducer) else { return nil }
        var body = bytes[introducer.count...]
        if body.last == 0x07 {
            body = body.dropLast()
        } else if body.count >= 2, body[body.endIndex - 1] == 0x5c, body[body.endIndex - 2] == 0x1b {
            body = body.dropLast(2)
        } else {
            return nil
        }
        // The selection field (`c`, `p`, `s`, a digit, or nothing) runs to the next semicolon.
        guard let separator = body.firstIndex(of: 0x3b) else { return nil }
        let payload = body[body.index(after: separator)...]
        guard !payload.isEmpty else { return .empty }
        guard let data = Data(base64Encoded: Data(payload)) else { return .unreadable }
        return .text(String(decoding: data, as: UTF8.self))
    }
}
