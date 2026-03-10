/// Static builders for Kitty-specific escape sequences.
public enum KittySequences: Sendable {

    // MARK: - Synchronized Output (mode 2026)

    /// Begin synchronized update — terminal buffers output until end.
    public static let beginSyncUpdate: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x68]
    // ESC [ ? 2 0 2 6 h

    /// End synchronized update — terminal flushes buffered output.
    public static let endSyncUpdate: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c]
    // ESC [ ? 2 0 2 6 l

    // MARK: - Keyboard Protocol (CSI u)

    /// Push keyboard mode with given flags onto the stack.
    /// flags is a bitmask: 1=disambiguate, 2=report-events, 4=report-alternates, 8=report-all, 16=report-associated
    public static func pushKeyboardMode(flags: UInt8) -> [UInt8] {
        // CSI > flags u
        var bytes: [UInt8] = [0x1b, 0x5b, 0x3e] // ESC [ >
        appendDecimal(&bytes, flags)
        bytes.append(0x75) // u
        return bytes
    }

    /// Pop keyboard mode from the stack.
    public static let popKeyboardMode: [UInt8] = [0x1b, 0x5b, 0x3c, 0x75]
    // ESC [ < u

    // MARK: - Mouse

    /// Enable SGR mouse mode (1006) — cell coordinates.
    public static let enableMouseSGR: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68, // CSI ? 1000 h (basic mouse)
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x68, // CSI ? 1002 h (button-event tracking)
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x68, // CSI ? 1003 h (all-motion tracking)
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x36, 0x68, // CSI ? 1006 h (SGR extended)
    ]

    /// Disable SGR mouse mode.
    public static let disableMouseSGR: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x36, 0x6c, // CSI ? 1006 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x6c, // CSI ? 1003 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x6c, // CSI ? 1002 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x6c, // CSI ? 1000 l
    ]

    /// Enable SGR pixel mouse mode (1016).
    public static let enableMousePixel: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68, // CSI ? 1000 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x68, // CSI ? 1002 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x68, // CSI ? 1003 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x31, 0x36, 0x68, // CSI ? 1016 h
    ]

    /// Disable SGR pixel mouse mode.
    public static let disableMousePixel: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x31, 0x36, 0x6c, // CSI ? 1016 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x6c, // CSI ? 1003 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x6c, // CSI ? 1002 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x6c, // CSI ? 1000 l
    ]

    // MARK: - Cursor

    /// Move cursor to row, col (1-based).
    public static func moveCursor(row: Int, col: Int) -> [UInt8] {
        // CSI row ; col H
        var bytes: [UInt8] = [0x1b, 0x5b]
        appendDecimal(&bytes, UInt16(row))
        bytes.append(0x3b)
        appendDecimal(&bytes, UInt16(col))
        bytes.append(0x48) // H
        return bytes
    }

    /// Hide cursor.
    public static let hideCursor: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x6c]
    // CSI ? 25 l

    /// Show cursor.
    public static let showCursor: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x68]
    // CSI ? 25 h

    // MARK: - Screen

    /// Enter alternate screen buffer.
    public static let enterAlternateScreen: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]
    // CSI ? 1049 h

    /// Leave alternate screen buffer.
    public static let leaveAlternateScreen: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c]
    // CSI ? 1049 l

    /// Clear entire screen.
    public static let clearScreen: [UInt8] = [0x1b, 0x5b, 0x32, 0x4a]
    // CSI 2 J

    // MARK: - Clipboard (OSC 52)

    /// Set clipboard content (base64-encoded).
    public static func setClipboard(_ base64Content: String) -> [UInt8] {
        // OSC 52 ; c ; <base64> ST
        var bytes: [UInt8] = [0x1b, 0x5d] // ESC ]
        bytes.append(contentsOf: "52;c;".utf8)
        bytes.append(contentsOf: base64Content.utf8)
        bytes.append(0x1b) // ESC
        bytes.append(0x5c) // \ (ST)
        return bytes
    }

    /// Request clipboard content.
    public static let requestClipboard: [UInt8] = [
        0x1b, 0x5d, 0x35, 0x32, 0x3b, 0x63, 0x3b, 0x3f, 0x1b, 0x5c,
    ]
    // OSC 52 ; c ; ? ST

    // MARK: - Notifications (OSC 99)

    /// Send a desktop notification.
    public static func notify(title: String, body: String = "") -> [UInt8] {
        // OSC 99 ; i=1:d=0:p=title ; <title> ST
        var bytes: [UInt8] = [0x1b, 0x5d] // ESC ]
        bytes.append(contentsOf: "99;i=1:d=0:p=title;".utf8)
        bytes.append(contentsOf: title.utf8)
        bytes.append(0x1b)
        bytes.append(0x5c)
        if !body.isEmpty {
            bytes.append(0x1b)
            bytes.append(0x5d)
            bytes.append(contentsOf: "99;i=1:d=0:p=body;".utf8)
            bytes.append(contentsOf: body.utf8)
            bytes.append(0x1b)
            bytes.append(0x5c)
        }
        return bytes
    }

    // MARK: - Focus Events

    /// Enable focus event reporting.
    public static let enableFocusEvents: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x34, 0x68]
    // CSI ? 1004 h

    /// Disable focus event reporting.
    public static let disableFocusEvents: [UInt8] = [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x34, 0x6c]
    // CSI ? 1004 l

    // MARK: - Bracketed Paste

    /// Enable bracketed paste mode.
    public static let enableBracketedPaste: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68]
    // CSI ? 2004 h

    /// Disable bracketed paste mode.
    public static let disableBracketedPaste: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x6c]
    // CSI ? 2004 l

    // MARK: - Private

    private static func appendDecimal(_ bytes: inout [UInt8], _ value: UInt16) {
        if value >= 100 {
            if value >= 1000 {
                bytes.append(0x30 + UInt8(value / 1000))
                bytes.append(0x30 + UInt8((value / 100) % 10))
            } else {
                bytes.append(0x30 + UInt8(value / 100))
            }
            bytes.append(0x30 + UInt8((value / 10) % 10))
            bytes.append(0x30 + UInt8(value % 10))
        } else if value >= 10 {
            bytes.append(0x30 + UInt8(value / 10))
            bytes.append(0x30 + UInt8(value % 10))
        } else {
            bytes.append(0x30 + UInt8(value))
        }
    }

    private static func appendDecimal(_ bytes: inout [UInt8], _ value: UInt8) {
        appendDecimal(&bytes, UInt16(value))
    }
}
