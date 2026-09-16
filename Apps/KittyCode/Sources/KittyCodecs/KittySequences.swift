/// Static builders for Kitty terminal-specific escape sequences.
///
/// Covers synchronized output (mode 2026), the Kitty keyboard protocol (CSI u),
/// SGR and pixel mouse modes, cursor control, alternate screen, clipboard (OSC 52),
/// desktop notifications (OSC 99), focus events, and bracketed paste.
public enum KittySequences: Sendable {

    // MARK: - Lookup table for decimal encoding

    /// Pre-computed decimal digits for values 0-65535.
    private static let decimalTable: [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)] = {
        var table = [(UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)](
            repeating: (0, 0, 0, 0, 0, 0), count: 65536)
        for i in 0..<65536 {
            let d5 = UInt8(i / 10_000)
            let d4 = UInt8((i / 1_000) % 10)
            let d3 = UInt8((i / 100) % 10)
            let d2 = UInt8((i / 10) % 10)
            let d1 = UInt8(i % 10)
            let count: UInt8
            if i >= 10_000 {
                count = 5
            } else if i >= 1_000 {
                count = 4
            } else if i >= 100 {
                count = 3
            } else if i >= 10 {
                count = 2
            } else {
                count = 1
            }
            table[i] = (0x30 + d5, 0x30 + d4, 0x30 + d3, 0x30 + d2, 0x30 + d1, count)
        }
        return table
    }()

    // MARK: - Synchronized Output (mode 2026)

    /// Begin synchronized update — terminal buffers output until end.
    public static let beginSyncUpdate: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x68]
    // ESC [ ? 2 0 2 6 h

    /// End synchronized update — terminal flushes buffered output.
    public static let endSyncUpdate: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x32, 0x36, 0x6c]
    // ESC [ ? 2 0 2 6 l

    // MARK: - Keyboard Protocol (CSI u)

    /// Push a keyboard mode with the given flags onto the terminal's mode stack.
    ///
    /// - Parameter flags: A bitmask of reporting flags — 1: disambiguate, 2: report-events,
    ///   4: report-alternates, 8: report-all, 16: report-associated.
    /// - Returns: Raw bytes for the `CSI > flags u` sequence.
    public static func pushKeyboardMode(flags: UInt8) -> [UInt8] {
        // CSI > flags u
        var bytes: [UInt8] = [0x1b, 0x5b, 0x3e]  // ESC [ >
        appendDecimalLegacy(&bytes, flags)
        bytes.append(0x75)  // u
        return bytes
    }

    /// Pop keyboard mode from the stack.
    public static let popKeyboardMode: [UInt8] = [0x1b, 0x5b, 0x3c, 0x75]
    // ESC [ < u

    // MARK: - Mouse

    /// Enable SGR mouse mode (1006) — cell coordinates with button-event (drag) tracking.
    public static let enableMouseSGR: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68,  // CSI ? 1000 h (basic mouse)
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x68,  // CSI ? 1002 h (button-event / drag)
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x36, 0x68,  // CSI ? 1006 h (SGR extended)
    ]

    /// Disable SGR mouse mode.
    public static let disableMouseSGR: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x36, 0x6c,  // CSI ? 1006 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x6c,  // CSI ? 1002 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x6c,  // CSI ? 1000 l
    ]

    /// Enable SGR pixel mouse mode (1016).
    public static let enableMousePixel: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68,  // CSI ? 1000 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x68,  // CSI ? 1002 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x68,  // CSI ? 1003 h
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x31, 0x36, 0x68,  // CSI ? 1016 h
    ]

    /// Disable SGR pixel mouse mode.
    public static let disableMousePixel: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x31, 0x36, 0x6c,  // CSI ? 1016 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x33, 0x6c,  // CSI ? 1003 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x32, 0x6c,  // CSI ? 1002 l
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x6c,  // CSI ? 1000 l
    ]

    // MARK: - Cursor

    /// Move the cursor to the specified 1-based row and column position.
    ///
    /// Both coordinates are clamped to the range `1...65535` before encoding.
    ///
    /// - Parameters:
    ///   - row: The target row (1-based).
    ///   - col: The target column (1-based).
    /// - Returns: Raw bytes for the `CSI row ; col H` sequence.
    public static func moveCursor(row: Int, col: Int) -> [UInt8] {
        // CSI row ; col H
        var bytes: [UInt8] = [0x1b, 0x5b]
        appendDecimalLegacy(&bytes, clampedCursorCoordinate(row))
        bytes.append(0x3b)
        appendDecimalLegacy(&bytes, clampedCursorCoordinate(col))
        bytes.append(0x48)  // H
        return bytes
    }

    /// Appends a cursor movement sequence directly into a ContiguousArray buffer (zero-allocation).
    @inline(__always)
    public static func appendMoveCursor(row: Int, col: Int, to bytes: inout ContiguousArray<UInt8>)
    {
        bytes.append(0x1b)  // ESC
        bytes.append(0x5b)  // [
        appendDecimal(&bytes, clampedCursorCoordinate(row))
        bytes.append(0x3b)  // ;
        appendDecimal(&bytes, clampedCursorCoordinate(col))
        bytes.append(0x48)  // H
    }

    /// Appends begin sync update sequence to a buffer.
    @inline(__always)
    public static func appendBeginSyncUpdate(to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(contentsOf: beginSyncUpdate)
    }

    /// Appends end sync update sequence to a buffer.
    @inline(__always)
    public static func appendEndSyncUpdate(to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(contentsOf: endSyncUpdate)
    }

    /// Appends hide cursor sequence to a buffer.
    @inline(__always)
    public static func appendHideCursor(to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(contentsOf: hideCursor)
    }

    /// Appends show cursor sequence to a buffer.
    @inline(__always)
    public static func appendShowCursor(to bytes: inout ContiguousArray<UInt8>) {
        bytes.append(contentsOf: showCursor)
    }

    /// Hide cursor.
    public static let hideCursor: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x6c]
    // CSI ? 25 l

    /// Show cursor.
    public static let showCursor: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x35, 0x68]
    // CSI ? 25 h

    // MARK: - Screen

    /// Enter alternate screen buffer.
    public static let enterAlternateScreen: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68,
    ]
    // CSI ? 1049 h

    /// Leave alternate screen buffer.
    public static let leaveAlternateScreen: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c,
    ]
    // CSI ? 1049 l

    /// Clear entire screen.
    public static let clearScreen: [UInt8] = [0x1b, 0x5b, 0x32, 0x4a]
    // CSI 2 J

    // MARK: - Clipboard (OSC 52)

    /// Set the system clipboard to the provided base64-encoded content via OSC 52.
    ///
    /// - Parameter base64Content: A base64-encoded string representing the desired clipboard payload.
    /// - Returns: Raw bytes for the `OSC 52 ; c ; <base64> ST` sequence.
    public static func setClipboard(_ base64Content: String) -> [UInt8] {
        // OSC 52 ; c ; <base64> ST
        var bytes: [UInt8] = [0x1b, 0x5d]  // ESC ]
        bytes.append(contentsOf: "52;c;".utf8)
        bytes.append(contentsOf: base64Content.utf8)
        bytes.append(0x1b)  // ESC
        bytes.append(0x5c)  // \ (ST)
        return bytes
    }

    /// Request clipboard content.
    public static let requestClipboard: [UInt8] = [
        0x1b, 0x5d, 0x35, 0x32, 0x3b, 0x63, 0x3b, 0x3f, 0x1b, 0x5c,
    ]
    // OSC 52 ; c ; ? ST

    // MARK: - Notifications (OSC 99)

    /// Send a desktop notification via the Kitty OSC 99 protocol.
    ///
    /// When `body` is non-empty, a second OSC 99 segment is appended carrying the body text.
    ///
    /// - Parameters:
    ///   - title: The notification title.
    ///   - body: An optional notification body. Defaults to an empty string (omitted).
    /// - Returns: Raw bytes encoding one or two OSC 99 sequences.
    public static func notify(title: String, body: String = "") -> [UInt8] {
        // OSC 99 ; i=1:d=0:p=title ; <title> ST
        var bytes: [UInt8] = [0x1b, 0x5d]  // ESC ]
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
    public static let disableFocusEvents: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x34, 0x6c,
    ]
    // CSI ? 1004 l

    // MARK: - Bracketed Paste

    /// Enable bracketed paste mode.
    public static let enableBracketedPaste: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68,
    ]
    // CSI ? 2004 h

    /// Disable bracketed paste mode.
    public static let disableBracketedPaste: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x6c,
    ]
    // CSI ? 2004 l

    // MARK: - Scroll Regions (DECSTBM) & Index

    /// Sets the scrolling region to rows `top`…`bottom` (1-based, inclusive).
    ///
    /// Content outside this region is unaffected by SU/SD scroll commands.
    /// Call `appendResetScrollRegion` to restore full-screen scrolling.
    @inline(__always)
    public static func appendSetScrollRegion(
        top: Int, bottom: Int, to bytes: inout ContiguousArray<UInt8>
    ) {
        // CSI top ; bottom r
        bytes.append(0x1b)
        bytes.append(0x5b)
        appendDecimal(&bytes, clampedCursorCoordinate(top))
        bytes.append(0x3b)
        appendDecimal(&bytes, clampedCursorCoordinate(bottom))
        bytes.append(0x72)  // r
    }

    /// Resets the scrolling region to the full terminal screen.
    @inline(__always)
    public static func appendResetScrollRegion(to bytes: inout ContiguousArray<UInt8>) {
        // CSI r
        bytes.append(0x1b)
        bytes.append(0x5b)
        bytes.append(0x72)
    }

    /// Scrolls the content within the active scroll region up by `n` lines.
    ///
    /// Lines at the top are removed; new blank lines appear at the bottom.
    @inline(__always)
    public static func appendScrollUp(lines: Int, to bytes: inout ContiguousArray<UInt8>) {
        // CSI n S
        bytes.append(0x1b)
        bytes.append(0x5b)
        appendDecimal(&bytes, clampedCursorCoordinate(lines))
        bytes.append(0x53)  // S
    }

    /// Scrolls the content within the active scroll region down by `n` lines.
    ///
    /// Lines at the bottom are removed; new blank lines appear at the top.
    @inline(__always)
    public static func appendScrollDown(lines: Int, to bytes: inout ContiguousArray<UInt8>) {
        // CSI n T
        bytes.append(0x1b)
        bytes.append(0x5b)
        appendDecimal(&bytes, clampedCursorCoordinate(lines))
        bytes.append(0x54)  // T
    }

    // MARK: - Private

    /// Decimal encoding for the optimized ContiguousArray path using lookup table.
    @inline(__always)
    private static func appendDecimal(_ bytes: inout ContiguousArray<UInt8>, _ value: UInt16) {
        let entry = decimalTable[Int(value)]
        switch entry.5 {
        case 5:
            bytes.append(entry.0)
            bytes.append(entry.1)
            bytes.append(entry.2)
            bytes.append(entry.3)
            bytes.append(entry.4)
        case 4:
            bytes.append(entry.1)
            bytes.append(entry.2)
            bytes.append(entry.3)
            bytes.append(entry.4)
        case 3:
            bytes.append(entry.2)
            bytes.append(entry.3)
            bytes.append(entry.4)
        case 2:
            bytes.append(entry.3)
            bytes.append(entry.4)
        default:
            bytes.append(entry.4)
        }
    }

    @inline(__always)
    private static func appendDecimal(_ bytes: inout ContiguousArray<UInt8>, _ value: UInt8) {
        appendDecimal(&bytes, UInt16(value))
    }

    /// Legacy [UInt8] path for backward compatibility (static let properties, pushKeyboardMode, etc.)
    private static func appendDecimalLegacy(_ bytes: inout [UInt8], _ value: UInt16) {
        if value >= 10_000 {
            bytes.append(0x30 + UInt8(value / 10_000))
        }
        if value >= 1_000 {
            bytes.append(0x30 + UInt8((value / 1_000) % 10))
        }
        if value >= 100 {
            bytes.append(0x30 + UInt8((value / 100) % 10))
        }
        if value >= 10 {
            bytes.append(0x30 + UInt8((value / 10) % 10))
        }
        bytes.append(0x30 + UInt8(value % 10))
    }

    private static func appendDecimalLegacy(_ bytes: inout [UInt8], _ value: UInt8) {
        appendDecimalLegacy(&bytes, UInt16(value))
    }

    private static func clampedCursorCoordinate(_ value: Int) -> UInt16 {
        UInt16(Swift.max(1, Swift.min(65_535, value)))
    }
}
