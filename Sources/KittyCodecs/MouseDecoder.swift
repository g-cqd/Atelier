/// Decodes SGR mouse events (mode 1006 and 1016).
///
/// Format: `CSI < Cb ; Cx ; Cy M` (press) or `CSI < Cb ; Cx ; Cy m` (release)
/// Mode 1016 uses pixel coordinates instead of cell coordinates.
public struct MouseDecoder: Sendable {
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
            if byte == 0x5b { // [
                state = .csi
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .csi:
            if byte == 0x3c { // <
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
                buttonBits = buttonBits * 10 + UInt16(byte - 0x30)
                return .pending
            }
            if byte == 0x3b { // ;
                state = .coordX
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .coordX:
            if isDigit(byte) {
                coordX = coordX * 10 + Int(byte - 0x30)
                return .pending
            }
            if byte == 0x3b { // ;
                state = .coordY
                return .pending
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .coordY:
            if isDigit(byte) {
                coordY = coordY * 10 + Int(byte - 0x30)
                return .pending
            }
            if byte == 0x4d || byte == 0x6d { // M (press) or m (release)
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

        if isScroll {
            button = rawButton == 0 ? .scrollUp : rawButton == 1 ? .scrollDown :
                     rawButton == 2 ? .scrollLeft : .scrollRight
            kind = .press
        } else if isRelease {
            button = MouseButton(rawValue: UInt8(rawButton)) ?? .left
            kind = .release
        } else if isMotion {
            button = MouseButton(rawValue: UInt8(rawButton)) ?? .left
            kind = rawButton == 3 ? .motion : .drag
        } else {
            button = MouseButton(rawValue: UInt8(rawButton)) ?? .left
            kind = .press
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
}
