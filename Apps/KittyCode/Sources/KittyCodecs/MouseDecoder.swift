/// Decodes SGR mouse events (mode 1006 and 1016).
///
/// Format: `CSI < Cb ; Cx ; Cy M` (press) or `CSI < Cb ; Cx ; Cy m` (release)
/// Mode 1016 uses pixel coordinates instead of cell coordinates.
public struct MouseDecoder: Sendable {
    /// Hard cap on the in-flight buffer length. A legal SGR mouse
    /// sequence is at most ~30 bytes; this is a defence-in-depth ceiling
    /// against malformed streams that never reach a terminator.
    private static let maxSequenceBytes = 256

    private enum State: Sendable {
        case ground
        case escape
        case csi
        case lt
        case button
        case coordX
        case coordY
    }

    private var state: State = .ground
    private var buffer: [UInt8] = []
    private var buttonBits: UInt16 = 0
    private var coordX: Int = 0
    private var coordY: Int = 0
    public var pixelMode: Bool

    public init(pixelMode: Bool = false) {
        self.pixelMode = pixelMode
    }

    public mutating func feed(_ byte: UInt8) -> DecoderResult<MouseEvent> {
        buffer.append(byte)
        if buffer.count > Self.maxSequenceBytes {
            return invalidResult()
        }

        switch state {
        case .ground:
            if byte == 0x1b {
                state = .escape
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .escape:
            if byte == 0x5b {  // [
                state = .csi
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .csi:
            if byte == 0x3c {  // <
                state = .lt
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .lt:
            if isDigit(byte) {
                state = .button
                buttonBits = UInt16(byte - 0x30)
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .button:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &buttonBits, maximum: UInt16.max) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3b {  // ;
                state = .coordX
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .coordX:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &coordX, maximum: 65_535) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3b {  // ;
                state = .coordY
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .coordY:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &coordY, maximum: 65_535) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x4d || byte == 0x6d {  // M (press) or m (release)
                let isRelease = byte == 0x6d
                let event = decodeEvent(isRelease: isRelease)
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)
        }
    }

    private func decodeEvent(isRelease: Bool) -> MouseEvent {
        // Button bits: lower 2 bits = button, bit 5 = motion, bits 2-4 = modifiers
        let rawButton = buttonBits & 0x03
        let isMotion = (buttonBits & 32) != 0
        let isScroll = (buttonBits & 64) != 0

        let button: MouseButton
        let kind: MouseEventKind

        if buttonBits >= 128 {
            button = extraButton(from: rawButton)
            kind = eventKind(isRelease: isRelease, isMotion: isMotion, rawButton: rawButton)
        } else if isScroll {
            button =
                rawButton == 0
                ? .scrollUp
                : rawButton == 1 ? .scrollDown : rawButton == 2 ? .scrollLeft : .scrollRight
            kind = .press
        } else {
            button = standardButton(from: rawButton)
            kind = eventKind(isRelease: isRelease, isMotion: isMotion, rawButton: rawButton)
        }

        // Modifiers from bits 2-4
        var mods = KeyModifiers()
        if buttonBits & 4 != 0 { mods.insert(.shift) }
        if buttonBits & 8 != 0 { mods.insert(.alt) }
        if buttonBits & 16 != 0 { mods.insert(.ctrl) }

        if pixelMode {
            return MouseEvent(
                button: button, modifiers: mods,
                row: 0, col: 0,
                pixelX: coordX, pixelY: coordY,
                kind: kind
            )
        } else {
            return MouseEvent(
                button: button, modifiers: mods,
                row: coordY, col: coordX,
                kind: kind
            )
        }
    }

    private mutating func reset() {
        state = .ground
        buffer.removeAll()
        buttonBits = 0
        coordX = 0
        coordY = 0
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private mutating func invalidResult() -> DecoderResult<MouseEvent> {
        let invalid = buffer
        reset()
        return .invalid(invalid)
    }

    private func standardButton(from rawButton: UInt16) -> MouseButton {
        MouseButton(rawValue: UInt8(rawButton)) ?? .left
    }

    private func extraButton(from rawButton: UInt16) -> MouseButton {
        switch rawButton {
        case 0, 2:
            .button4
        case 1, 3:
            .button5
        default:
            .button4
        }
    }

    private func eventKind(isRelease: Bool, isMotion: Bool, rawButton: UInt16) -> MouseEventKind {
        if isRelease {
            return .release
        }
        if isMotion {
            return rawButton == 3 ? .motion : .drag
        }
        return .press
    }

    private static func appendDigit<T: FixedWidthInteger>(
        _ digit: UInt8,
        to value: inout T,
        maximum: T
    ) -> Bool {
        let (multiplied, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
        guard !multiplyOverflow else {
            return false
        }

        let (updated, addOverflow) = multiplied.addingReportingOverflow(T(digit))
        guard !addOverflow, updated <= maximum else {
            return false
        }

        value = updated
        return true
    }
}
