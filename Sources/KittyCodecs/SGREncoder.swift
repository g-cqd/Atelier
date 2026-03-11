// MARK: - SGR Encoder

/// Converts `Style` values into ANSI/VT Select Graphic Rendition (SGR) escape sequences.
///
/// All methods produce raw UTF-8 byte arrays ready to be written directly to a terminal output stream.
public enum SGREncoder: Sendable {

    // MARK: - Lookup table for decimal encoding (0-255 -> ASCII digits)

    /// Pre-computed decimal digits for values 0-999.
    /// Each entry is (hundreds, tens, ones, digitCount).
    private static let decimalTable: [(UInt8, UInt8, UInt8, UInt8)] = {
        var table = [(UInt8, UInt8, UInt8, UInt8)](repeating: (0, 0, 0, 0), count: 1000)
        for i in 0..<1000 {
            let h = UInt8(i / 100)
            let t = UInt8((i / 10) % 10)
            let o = UInt8(i % 10)
            if i >= 100 {
                table[i] = (0x30 + h, 0x30 + t, 0x30 + o, 3)
            } else if i >= 10 {
                table[i] = (0, 0x30 + t, 0x30 + o, 2)
            } else {
                table[i] = (0, 0, 0x30 + o, 1)
            }
        }
        return table
    }()

    // MARK: - Full Encode

    /// Encodes a style into a complete SGR escape sequence.
    ///
    /// Returns an empty array when `style` equals `.default`, avoiding unnecessary output.
    ///
    /// - Parameter style: The style to encode.
    /// - Returns: Raw bytes for the SGR sequence, or an empty array if the style is the default.
    public static func encode(_ style: Style) -> [UInt8] {
        if style == .default { return [] }
        var params = ContiguousArray<UInt8>()
        params.reserveCapacity(32)
        encode(style, into: &params)
        return Array(params)
    }

    /// Encodes a style into a caller-provided buffer (zero-allocation path).
    public static func encode(_ style: Style, into params: inout ContiguousArray<UInt8>) {
        if style == .default { return }
        params.append(0x1b) // ESC
        params.append(0x5b) // [

        var first = true

        if style.bold { appendSep(&params, &first); params.append(0x31) } // 1
        if style.dim { appendSep(&params, &first); params.append(0x32) } // 2
        if style.italic { appendSep(&params, &first); params.append(0x33) } // 3

        if style.underline != .none {
            appendSep(&params, &first)
            // Kitty styled underlines: 4:N
            params.append(0x34) // 4
            params.append(0x3a) // :
            params.append(0x30 + style.underline.rawValue) // 0-5
        }

        if style.inverse { appendSep(&params, &first); params.append(0x37) } // 7
        if style.strikethrough { appendSep(&params, &first); params.append(0x39) } // 9

        if style.fg != .default {
            appendColor(&params, style.fg, foreground: true, first: &first)
        }
        if style.bg != .default {
            appendColor(&params, style.bg, foreground: false, first: &first)
        }
        if style.underlineColor != .default {
            appendUnderlineColor(&params, style.underlineColor, first: &first)
        }

        params.append(0x6d) // m
    }

    // MARK: - Diff Encode

    /// Encodes the minimal SGR sequence needed to transition from one style to another.
    ///
    /// Only the attributes that differ between `old` and `new` are included, reducing byte output.
    /// Returns an empty array when the styles are identical.
    ///
    /// - Parameters:
    ///   - old: The currently active style.
    ///   - new: The desired target style.
    /// - Returns: Raw bytes for the minimal SGR transition, or an empty array if the styles are equal.
    public static func encodeDiff(from old: Style, to new: Style) -> [UInt8] {
        var params = ContiguousArray<UInt8>()
        params.reserveCapacity(32)
        encodeDiff(from: old, to: new, into: &params)
        return Array(params)
    }

    /// Encodes the minimal SGR diff into a caller-provided buffer (zero-allocation path).
    public static func encodeDiff(from old: Style, to new: Style, into params: inout ContiguousArray<UInt8>) {
        if old == new { return }
        if new == .default { params.append(contentsOf: [0x1b, 0x5b, 0x6d] as ContiguousArray<UInt8>); return } // ESC[m (reset)
        if old == .default { encode(new, into: &params); return }

        params.append(0x1b) // ESC
        params.append(0x5b) // [

        var first = true

        let intensityChanged = old.bold != new.bold || old.dim != new.dim
        let requiresIntensityReset = (old.bold && !new.bold) || (old.dim && !new.dim)

        if intensityChanged {
            if requiresIntensityReset {
                appendSep(&params, &first)
                params.append(0x32); params.append(0x32) // 22
                if new.bold {
                    appendSep(&params, &first)
                    params.append(0x31) // 1
                }
                if new.dim {
                    appendSep(&params, &first)
                    params.append(0x32) // 2
                }
            } else {
                if new.bold {
                    appendSep(&params, &first)
                    params.append(0x31) // 1
                }
                if new.dim {
                    appendSep(&params, &first)
                    params.append(0x32) // 2
                }
            }
        }
        if old.italic != new.italic {
            appendSep(&params, &first)
            if new.italic { params.append(0x33) } // 3
            else { params.append(0x32); params.append(0x33) } // 23
        }
        if old.underline != new.underline {
            appendSep(&params, &first)
            if new.underline == .none {
                params.append(0x32); params.append(0x34) // 24
            } else {
                params.append(0x34); params.append(0x3a)
                params.append(0x30 + new.underline.rawValue)
            }
        }
        if old.inverse != new.inverse {
            appendSep(&params, &first)
            if new.inverse { params.append(0x37) } // 7
            else { params.append(0x32); params.append(0x37) } // 27
        }
        if old.strikethrough != new.strikethrough {
            appendSep(&params, &first)
            if new.strikethrough { params.append(0x39) } // 9
            else { params.append(0x32); params.append(0x39) } // 29
        }
        if old.fg != new.fg {
            appendColor(&params, new.fg, foreground: true, first: &first)
        }
        if old.bg != new.bg {
            appendColor(&params, new.bg, foreground: false, first: &first)
        }
        if old.underlineColor != new.underlineColor {
            appendUnderlineColor(&params, new.underlineColor, first: &first)
        }

        params.append(0x6d)
    }

    // MARK: - Reset

    /// The SGR reset sequence (`ESC[m`) that restores all attributes to their defaults.
    public static let reset: [UInt8] = [0x1b, 0x5b, 0x6d]

    /// Appends the SGR reset sequence to a buffer.
    @inline(__always)
    public static func appendReset(to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(0x1b)
        bytes.append(0x5b)
        bytes.append(0x6d)
    }

    // MARK: - Private

    @inline(__always)
    private static func appendSep(_ bytes: inout ContiguousArray<UInt8>, _ first: inout Bool) {
        if !first { bytes.append(0x3b) } // ;
        first = false
    }

    private static func appendColor(_ bytes: inout ContiguousArray<UInt8>, _ color: Color, foreground: Bool, first: inout Bool) {
        switch color {
        case .default:
            appendSep(&bytes, &first)
            // 39 = default fg, 49 = default bg
            if foreground {
                bytes.append(0x33); bytes.append(0x39)
            } else {
                bytes.append(0x34); bytes.append(0x39)
            }
        case .indexed(let idx):
            appendSep(&bytes, &first)
            if idx < 8 {
                // 30-37 fg, 40-47 bg
                let base: UInt8 = foreground ? 30 : 40
                appendDecimal(&bytes, base + idx)
            } else if idx < 16 {
                // 90-97 fg, 100-107 bg
                let base: UInt8 = foreground ? 90 : 100
                appendDecimal(&bytes, base + idx - 8)
            } else {
                // 38;5;N fg, 48;5;N bg
                let prefix: UInt8 = foreground ? 38 : 48
                appendDecimal(&bytes, prefix)
                bytes.append(0x3b)
                bytes.append(0x35) // 5
                bytes.append(0x3b)
                appendDecimal(&bytes, UInt16(idx))
            }
        case .rgb(let r, let g, let b):
            appendSep(&bytes, &first)
            let prefix: UInt8 = foreground ? 38 : 48
            appendDecimal(&bytes, prefix)
            bytes.append(0x3b)
            bytes.append(0x32) // 2
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(r))
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(g))
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(b))
        }
    }

    private static func appendUnderlineColor(_ bytes: inout ContiguousArray<UInt8>, _ color: Color, first: inout Bool) {
        appendSep(&bytes, &first)
        switch color {
        case .default:
            bytes.append(0x35); bytes.append(0x39) // 59
        case .indexed(let idx):
            bytes.append(0x35); bytes.append(0x38) // 58
            bytes.append(0x3b)
            bytes.append(0x35) // 5
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(idx))
        case .rgb(let r, let g, let b):
            bytes.append(0x35); bytes.append(0x38) // 58
            bytes.append(0x3b)
            bytes.append(0x32) // 2
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(r))
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(g))
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(b))
        }
    }

    @inline(__always)
    private static func appendDecimal(_ bytes: inout ContiguousArray<UInt8>, _ value: UInt8) {
        appendDecimal(&bytes, UInt16(value))
    }

    @inline(__always)
    private static func appendDecimal(_ bytes: inout ContiguousArray<UInt8>, _ value: UInt16) {
        let entry = decimalTable[Int(value)]
        switch entry.3 {
        case 3:
            bytes.append(entry.0)
            bytes.append(entry.1)
            bytes.append(entry.2)
        case 2:
            bytes.append(entry.1)
            bytes.append(entry.2)
        default:
            bytes.append(entry.2)
        }
    }
}
