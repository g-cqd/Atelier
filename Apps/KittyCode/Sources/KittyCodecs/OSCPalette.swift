/// The OSC 10, 11 and 4 colour queries a terminal answers with its palette, and the parser for the answers.
///
/// The query ends with a primary device-attributes request (`CSI c`): every terminal answers that one, so its
/// reply marks the end of the palette answers even on a terminal that ignores colour queries.
public enum OSCPalette: Sendable {
    /// One answered colour.
    public enum Reply: Sendable, Equatable {
        case foreground(ColorRGB)
        case background(ColorRGB)
        case ansi(index: Int, ColorRGB)
        /// The device-attributes reply that closes a query round.
        case end
    }

    /// The bytes asking for the foreground, the background and the first `ansiCount` ANSI slots, followed by
    /// the device-attributes request that terminates the round.
    public static func query(ansiCount: Int = 16) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.append(contentsOf: "\u{1b}]10;?\u{1b}\\".utf8)
        bytes.append(contentsOf: "\u{1b}]11;?\u{1b}\\".utf8)
        for index in 0 ..< max(0, min(ansiCount, 256)) {
            bytes.append(contentsOf: "\u{1b}]4;\(index);?\u{1b}\\".utf8)
        }
        bytes.append(contentsOf: "\u{1b}[c".utf8)
        return bytes
    }

    /// Parses one complete reply sequence, as the input router hands over an OSC or CSI it does not decode
    /// itself: `ESC ] 10 ; rgb:RRRR/GGGG/BBBB ST`, `ESC ] 4 ; n ; rgb:… ST` (BEL or `ESC \` terminated), or
    /// the `ESC [ ? … c` device-attributes reply. Anything else is nil.
    public static func parse(_ bytes: [UInt8]) -> Reply? {
        guard bytes.count >= 3, bytes[0] == 0x1b else { return nil }
        if bytes[1] == 0x5b {
            return bytes.last == 0x63 && bytes[2] == 0x3f ? .end : nil
        }
        guard bytes[1] == 0x5d else { return nil }
        var body = bytes[2...]
        if body.last == 0x07 {
            body = body.dropLast()
        } else if body.count >= 2, body[body.endIndex - 1] == 0x5c, body[body.endIndex - 2] == 0x1b {
            body = body.dropLast(2)
        } else {
            return nil
        }
        let fields = String(decoding: body, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        switch fields.first {
            case "10":
                guard fields.count == 2, let color = color(fields[1]) else { return nil }
                return .foreground(color)
            case "11":
                guard fields.count == 2, let color = color(fields[1]) else { return nil }
                return .background(color)
            case "4":
                guard fields.count == 3, let index = Int(fields[1]), (0 ..< 256).contains(index),
                    let color = color(fields[2])
                else {
                    return nil
                }
                return .ansi(index: index, color)
            default:
                return nil
        }
    }

    /// `rgb:R/G/B` with one to four hex digits per channel (scaled to 8 bits), or `#rrggbb`.
    static func color(_ text: Substring) -> ColorRGB? {
        if text.hasPrefix("#") {
            return ColorRGB(hex: String(text))
        }
        guard text.hasPrefix("rgb:") else { return nil }
        let channels = text.dropFirst(4).split(separator: "/", omittingEmptySubsequences: false)
        guard channels.count == 3 else { return nil }
        var values: [UInt8] = []
        for channel in channels {
            guard (1 ... 4).contains(channel.count), let value = UInt32(channel, radix: 16) else { return nil }
            let maximum = (UInt32(1) << (UInt32(channel.count) * 4)) - 1
            values.append(UInt8((value * 255 + maximum / 2) / maximum))
        }
        return ColorRGB(r: values[0], g: values[1], b: values[2])
    }
}
