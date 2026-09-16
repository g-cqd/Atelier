/// Decodes Kitty keyboard protocol (CSI u) sequences.
///
/// Format: `CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u`
///
/// The progressive enhancement flags determine which fields are present.
public struct KeyboardDecoder: Sendable {
    /// Hard cap on the in-flight buffer length. A hostile stream that
    /// dribbles bytes into a never-terminating CSI sequence cannot grow
    /// the decoder past this; on overflow the partial sequence is
    /// returned as `.invalid` and state resets to `.ground`.
    private static let maxSequenceBytes = 4096
    /// Hard cap on `alternateKeys.count`. A real Kitty keyboard chord
    /// uses at most a handful of alternates; this is a defence-in-depth
    /// cap against `CSI <kc>:1:1:1:1:...` style payloads.
    private static let maxAlternateKeys = 32
    /// Hard cap on `textCodepoints.count`. A single grapheme cluster
    /// rarely exceeds tens of codepoints; this is a defence-in-depth
    /// cap against `CSI <kc>;1:1:1:1:...` style payloads.
    private static let maxTextCodepoints = 256

    private enum State: Sendable {
        case ground
        case escape
        case csi
        case keyCode
        case alternateKeys
        case modifiers
        case eventType
        case textCodepoints
    }

    private var state: State = .ground
    private var buffer: [UInt8] = []
    private var keyCodeValue: UInt32 = 0
    private var alternateKeys: [UInt32] = []
    private var currentAlternate: UInt32 = 0
    private var modifierValue: UInt8 = 0
    private var eventTypeValue: UInt8 = 0
    private var textCodepoints: [UInt32] = []
    private var currentTextCP: UInt32 = 0
    private var hasModifiers = false
    private var hasEventType = false
    private var hasText = false

    public init() {}

    public mutating func feed(_ byte: UInt8) -> DecoderResult<KeyEvent> {
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
            // Plain ASCII character (no CSI wrapper)
            let event = KeyEvent(keyCode: UInt32(byte))
            reset()
            return .complete(event)

        case .escape:
            if byte == 0x5b {  // [
                state = .csi
                return .pending
            }
            // ESC + char = Alt+char
            let event = KeyEvent(keyCode: UInt32(byte), modifiers: .alt)
            reset()
            return .complete(event)

        case .csi:
            if isDigit(byte) {
                state = .keyCode
                keyCodeValue = UInt32(byte - 0x30)
                return .pending
            }
            if byte == 0x75 {  // u — empty CSI u
                let event = KeyEvent(keyCode: 0)
                reset()
                return .complete(event)
            }
            // Could be other CSI sequence — mark invalid for this decoder
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .keyCode:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &keyCodeValue, maximum: UInt32.max) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3a {  // : — alternate key codes follow
                state = .alternateKeys
                currentAlternate = 0
                return .pending
            }
            if byte == 0x3b {  // ; — modifiers follow
                state = .modifiers
                hasModifiers = true
                return .pending
            }
            if byte == 0x75 {  // u — end
                let event = KeyEvent(keyCode: keyCodeValue)
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .alternateKeys:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &currentAlternate, maximum: UInt32.max)
                else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3a {  // : — next alternate
                guard alternateKeys.count < Self.maxAlternateKeys else {
                    return invalidResult()
                }
                alternateKeys.append(currentAlternate)
                currentAlternate = 0
                return .pending
            }
            if byte == 0x3b {  // ; — modifiers follow
                alternateKeys.append(currentAlternate)
                state = .modifiers
                hasModifiers = true
                return .pending
            }
            if byte == 0x75 {  // u — end
                alternateKeys.append(currentAlternate)
                let event = KeyEvent(
                    keyCode: keyCodeValue,
                    alternateKeys: alternateKeys
                )
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .modifiers:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &modifierValue, maximum: UInt8.max) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3a {  // : — event type follows
                state = .eventType
                hasEventType = true
                return .pending
            }
            if byte == 0x3b {  // ; — text codepoints follow
                state = .textCodepoints
                hasText = true
                return .pending
            }
            if byte == 0x75 {  // u — end
                let event = makeEvent()
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .eventType:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &eventTypeValue, maximum: UInt8.max) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3b {  // ; — text codepoints follow
                state = .textCodepoints
                hasText = true
                return .pending
            }
            if byte == 0x75 {  // u — end
                let event = makeEvent()
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)

        case .textCodepoints:
            if isDigit(byte) {
                guard Self.appendDigit(byte - 0x30, to: &currentTextCP, maximum: UInt32.max) else {
                    return invalidResult()
                }
                return .pending
            }
            if byte == 0x3a {  // : — next codepoint
                guard textCodepoints.count < Self.maxTextCodepoints else {
                    return invalidResult()
                }
                textCodepoints.append(currentTextCP)
                currentTextCP = 0
                return .pending
            }
            if byte == 0x75 {  // u — end
                textCodepoints.append(currentTextCP)
                let event = makeEvent()
                reset()
                return .complete(event)
            }
            let invalid = buffer
            reset()
            return .invalid(invalid)
        }
    }

    private func makeEvent() -> KeyEvent {
        // Modifiers field is 1-based (1 = no modifiers)
        let mods: KeyModifiers
        if modifierValue > 0 {
            mods = KeyModifiers(rawValue: modifierValue - 1)
        } else {
            mods = []
        }

        let evtType: KeyEventType
        if hasEventType, let t = KeyEventType(rawValue: eventTypeValue) {
            evtType = t
        } else {
            evtType = .press
        }

        let text: String
        if hasText {
            let scalars = textCodepoints.compactMap { UnicodeScalar($0) }
            text = scalars.map(String.init).joined()
        } else {
            text = ""
        }

        return KeyEvent(
            keyCode: keyCodeValue,
            modifiers: mods,
            eventType: evtType,
            alternateKeys: alternateKeys,
            associatedText: text
        )
    }

    private mutating func reset() {
        state = .ground
        buffer.removeAll()
        keyCodeValue = 0
        alternateKeys.removeAll()
        currentAlternate = 0
        modifierValue = 0
        eventTypeValue = 0
        textCodepoints.removeAll()
        currentTextCP = 0
        hasModifiers = false
        hasEventType = false
        hasText = false
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }

    private mutating func invalidResult() -> DecoderResult<KeyEvent> {
        let invalid = buffer
        reset()
        return .invalid(invalid)
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
