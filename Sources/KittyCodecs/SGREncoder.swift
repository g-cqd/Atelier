// MARK: - SGR Encoder

public enum SGREncoder: Sendable {

    // MARK: - Full Encode

    /// Encodes a Style into SGR escape sequence bytes.
    /// Returns empty array if style is default.
    public static func encode(_ style: Style) -> [UInt8] {
        if style == .default { return [] }
        var params: [UInt8] = []
        params.append(contentsOf: [0x1b, 0x5b]) // ESC[

        var first = true
        func sep() {
            if !first { params.append(0x3b) } // ;
            first = false
        }

        if style.bold { sep(); params.append(0x31) } // 1
        if style.dim { sep(); params.append(0x32) } // 2
        if style.italic { sep(); params.append(0x33) } // 3

        if style.underline != .none {
            sep()
            // Kitty styled underlines: 4:N
            params.append(0x34) // 4
            params.append(0x3a) // :
            params.append(0x30 + style.underline.rawValue) // 0-5
        }

        if style.inverse { sep(); params.append(0x37) } // 7
        if style.strikethrough { sep(); params.append(0x39) } // 9

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
        return params
    }

    // MARK: - Diff Encode

    /// Encodes the minimal SGR transition from `old` to `new`.
    public static func encodeDiff(from old: Style, to new: Style) -> [UInt8] {
        if old == new { return [] }
        if new == .default { return [0x1b, 0x5b, 0x6d] } // ESC[m (reset)
        if old == .default { return encode(new) }

        var params: [UInt8] = []
        params.append(contentsOf: [0x1b, 0x5b])

        var first = true
        func sep() {
            if !first { params.append(0x3b) }
            first = false
        }

        // Check each attribute individually
        if old.bold != new.bold {
            sep()
            if new.bold { params.append(0x31) } // 1
            else { params.append(contentsOf: [0x32, 0x32]) } // 22
        }
        if old.dim != new.dim {
            sep()
            if new.dim { params.append(0x32) } // 2
            else { params.append(contentsOf: [0x32, 0x32]) } // 22
        }
        if old.italic != new.italic {
            sep()
            if new.italic { params.append(0x33) } // 3
            else { params.append(contentsOf: [0x32, 0x33]) } // 23
        }
        if old.underline != new.underline {
            sep()
            if new.underline == .none {
                params.append(contentsOf: [0x32, 0x34]) // 24
            } else {
                params.append(0x34); params.append(0x3a)
                params.append(0x30 + new.underline.rawValue)
            }
        }
        if old.inverse != new.inverse {
            sep()
            if new.inverse { params.append(0x37) } // 7
            else { params.append(contentsOf: [0x32, 0x37]) } // 27
        }
        if old.strikethrough != new.strikethrough {
            sep()
            if new.strikethrough { params.append(0x39) } // 9
            else { params.append(contentsOf: [0x32, 0x39]) } // 29
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
        return params
    }

    // MARK: - Reset

    public static let reset: [UInt8] = [0x1b, 0x5b, 0x6d]

    // MARK: - Private

    private static func appendColor(_ bytes: inout [UInt8], _ color: Color, foreground: Bool, first: inout Bool) {
        switch color {
        case .default:
            if !first { bytes.append(0x3b) }
            first = false
            // 39 = default fg, 49 = default bg
            if foreground {
                bytes.append(contentsOf: [0x33, 0x39])
            } else {
                bytes.append(contentsOf: [0x34, 0x39])
            }
        case .indexed(let idx):
            if !first { bytes.append(0x3b) }
            first = false
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
            if !first { bytes.append(0x3b) }
            first = false
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

    private static func appendUnderlineColor(_ bytes: inout [UInt8], _ color: Color, first: inout Bool) {
        if !first { bytes.append(0x3b) }
        first = false
        switch color {
        case .default:
            bytes.append(contentsOf: [0x35, 0x39]) // 59
        case .indexed(let idx):
            bytes.append(contentsOf: [0x35, 0x38]) // 58
            bytes.append(0x3b)
            bytes.append(0x35) // 5
            bytes.append(0x3b)
            appendDecimal(&bytes, UInt16(idx))
        case .rgb(let r, let g, let b):
            bytes.append(contentsOf: [0x35, 0x38]) // 58
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

    private static func appendDecimal(_ bytes: inout [UInt8], _ value: UInt8) {
        appendDecimal(&bytes, UInt16(value))
    }

    private static func appendDecimal(_ bytes: inout [UInt8], _ value: UInt16) {
        if value >= 100 {
            bytes.append(0x30 + UInt8(value / 100))
            bytes.append(0x30 + UInt8((value / 10) % 10))
            bytes.append(0x30 + UInt8(value % 10))
        } else if value >= 10 {
            bytes.append(0x30 + UInt8(value / 10))
            bytes.append(0x30 + UInt8(value % 10))
        } else {
            bytes.append(0x30 + UInt8(value))
        }
    }
}
