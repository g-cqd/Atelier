import KittyCodecs

/// Routes incoming byte sequences to appropriate decoders based on prefix.
public struct SequenceRouter: Sendable {
    private enum RouteState: Sendable {
        case ground
        case escape
        case csi
        case csiLt
        case csiGt
        case csiParam
        case keyboard
        case mouse
        case osc
        case paste
        case ss3
        case utf8Sequence
    }

    private enum FunctionalKeyCode {
        static let insert: UInt32 = 57348
        static let delete: UInt32 = 57349
        static let up: UInt32 = 57352
        static let down: UInt32 = 57353
        static let right: UInt32 = 57354
        static let left: UInt32 = 57355
        static let home: UInt32 = 57356
        static let end: UInt32 = 57357
        static let pageUp: UInt32 = 57358
        static let pageDown: UInt32 = 57359
        static let f1: UInt32 = 57364
        static let f2: UInt32 = 57365
        static let f3: UInt32 = 57366
        static let f4: UInt32 = 57367
    }

    private static let pasteEndMarker: [UInt8] = [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]
    private static let oscOverflowBytes = Array("osc overflow".utf8)
    private static let pasteOverflowBytes = Array("paste overflow".utf8)

    private static let maxPasteSize = 1_048_576  // 1MB

    private var keyboardDecoder = KeyboardDecoder()
    private var mouseDecoder = MouseDecoder()
    private var buffer: [UInt8] = []
    private var routeState: RouteState = .ground
    private var utf8Buffer: [UInt8] = []
    private var utf8ExpectedBytes: Int = 0

    public init() {}

    public mutating func feed(_ byte: UInt8) -> [InputEvent] {
        var events: [InputEvent] = []
        feed(byte, into: &events)
        return events
    }

    private mutating func feed(_ byte: UInt8, into events: inout [InputEvent]) {
        switch routeState {
        case .ground:
            if byte == 0x1b {
                routeState = .escape
                buffer = [byte]
            } else if (byte & 0b1000_0000) == 0 {
                if case .complete(let key) = keyboardDecoder.feed(byte) {
                    events.append(.key(key))
                }
            } else if (byte & 0b1110_0000) == 0b1100_0000 {
                utf8Buffer = [byte]
                utf8ExpectedBytes = 2
                routeState = .utf8Sequence
            } else if (byte & 0b1110_0000) == 0b1110_0000 {
                utf8Buffer = [byte]
                utf8ExpectedBytes = 3
                routeState = .utf8Sequence
            } else if (byte & 0b1111_0000) == 0b1111_0000 {
                utf8Buffer = [byte]
                utf8ExpectedBytes = 4
                routeState = .utf8Sequence
            }

        case .escape:
            buffer.append(byte)

            switch byte {
            case 0x5b:
                routeState = .csi
            case 0x5d:
                routeState = .osc
            case 0x4f:
                routeState = .ss3
            default:
                events.append(contentsOf: decodeKeyboardSequence(buffer))
                resetRouting()
            }

        case .csi:
            buffer.append(byte)

            switch byte {
            case 0x3c:
                routeState = .csiLt
            case 0x3e:
                routeState = .csiGt
            case 0x49:
                events.append(.focusIn)
                resetRouting()
            case 0x4f:
                events.append(.focusOut)
                resetRouting()
            case 0x75:
                events.append(contentsOf: decodeKeyboardSequence(buffer))
                resetRouting()
            case 0x30...0x39:
                routeState = .csiParam
            default:
                if let keyCode = Self.csiKeyCode(for: byte) {
                    events.append(.key(KeyEvent(keyCode: keyCode)))
                } else {
                    events.append(.unknown(buffer))
                }
                resetRouting()
            }

        case .csiLt:
            buffer.append(byte)
            routeState = .mouse
            for bufferedByte in buffer {
                _ = mouseDecoder.feed(bufferedByte)
            }

        case .csiGt:
            buffer.append(byte)
            routeState = .keyboard
            for bufferedByte in buffer {
                _ = keyboardDecoder.feed(bufferedByte)
            }

        case .csiParam:
            buffer.append(byte)

            if Self.isDigit(byte) || byte == 0x3a || byte == 0x3b {
                break
            }

            if byte == 0x75 {
                events.append(contentsOf: decodeKeyboardSequence(buffer))
                resetRouting()
                break
            }

            // Parse all semicolon-separated CSI params.
            // Format: CSI [firstParam] ; [modifierParam][:eventType] [terminator]
            // The modifier byte is 1-based: 1 = no modifier, 2 = shift, 3 = alt, etc.
            // The event type after ':' is: 1 = press, 2 = repeat, 3 = release.
            let parsed = parsedCSIParams()
            let firstParam = parsed.firstParam
            let modifierByte = parsed.modifier
            let mods = KeyModifiers(rawValue: UInt8(clamping: max(0, modifierByte - 1)))
            let eventType = parsed.eventType

            switch byte {
            case 0x7e:
                if firstParam == 200 {
                    routeState = .paste
                    buffer.removeAll(keepingCapacity: true)
                } else if let keyCode = Self.csiTildeKeyCode(for: firstParam) {
                    events.append(
                        .key(KeyEvent(keyCode: keyCode, modifiers: mods, eventType: eventType)))
                    resetRouting()
                } else {
                    events.append(.unknown(buffer))
                    resetRouting()
                }
            default:
                if let keyCode = Self.csiKeyCode(for: byte) {
                    events.append(
                        .key(KeyEvent(keyCode: keyCode, modifiers: mods, eventType: eventType)))
                } else {
                    events.append(.unknown(buffer))
                }
                resetRouting()
            }

        case .keyboard:
            let result = keyboardDecoder.feed(byte)
            switch result {
            case .complete(let key):
                events.append(.key(key))
                resetRouting()
            case .invalid(let bytes):
                events.append(.unknown(bytes))
                resetRouting()
            case .pending:
                break
            }

        case .mouse:
            let result = mouseDecoder.feed(byte)
            switch result {
            case .complete(let mouse):
                events.append(.mouse(mouse))
                resetRouting()
            case .invalid(let bytes):
                events.append(.unknown(bytes))
                resetRouting()
            case .pending:
                break
            }

        case .osc:
            buffer.append(byte)
            if buffer.count > Self.maxPasteSize {
                // OSC sequence too large — discard
                events.append(.unknown(Self.oscOverflowBytes))
                resetRouting()
            } else if byte == 0x07 {
                events.append(.unknown(buffer))
                resetRouting()
            } else if buffer.count >= 2, buffer[buffer.count - 2] == 0x1b, byte == 0x5c {
                events.append(.unknown(buffer))
                resetRouting()
            }

        case .paste:
            buffer.append(byte)
            if buffer.count > Self.maxPasteSize {
                // Paste too large — discard and reset
                events.append(.unknown(Self.pasteOverflowBytes))
                resetRouting()
            } else if buffer.count >= Self.pasteEndMarker.count,
                buffer.suffix(Self.pasteEndMarker.count).elementsEqual(Self.pasteEndMarker)
            {
                let text = String(
                    decoding: buffer.dropLast(Self.pasteEndMarker.count), as: UTF8.self)
                events.append(.paste(text))
                resetRouting()
            }

        case .ss3:
            if let keyCode = Self.ss3KeyCode(for: byte) {
                events.append(.key(KeyEvent(keyCode: keyCode)))
                resetRouting()
            } else {
                events.append(contentsOf: decodeKeyboardSequence([0x1b, 0x4f]))
                resetRouting()
                feed(byte, into: &events)
            }

        case .utf8Sequence:
            utf8Buffer.append(byte)
            if utf8Buffer.count >= utf8ExpectedBytes {
                let text = String(decoding: utf8Buffer, as: UTF8.self)
                if let scalar = text.unicodeScalars.first {
                    let event = KeyEvent(
                        keyCode: UInt32(scalar.value),
                        associatedText: text
                    )
                    events.append(.key(event))
                }
                resetRouting()
            }
        }
    }

    /// Feed a chunk of bytes and collect all emitted events.
    public mutating func feedAll(_ bytes: [UInt8]) -> [InputEvent] {
        var events: [InputEvent] = []
        feedAll(bytes, into: &events)
        return events
    }

    mutating func feedAll(_ bytes: UnsafeRawBufferPointer, into events: inout [InputEvent]) {
        events.removeAll(keepingCapacity: true)
        guard let baseAddress = bytes.baseAddress else { return }
        let typedBytes = UnsafeBufferPointer(
            start: baseAddress.assumingMemoryBound(to: UInt8.self),
            count: bytes.count
        )
        feedAll(typedBytes, into: &events)
    }

    private mutating func feedAll<S: Sequence>(_ bytes: S, into events: inout [InputEvent])
    where S.Element == UInt8 {
        events.removeAll(keepingCapacity: true)
        events.reserveCapacity(max(1, bytes.underestimatedCount))
        for byte in bytes {
            feed(byte, into: &events)
        }
    }

    private mutating func decodeKeyboardSequence<S: Sequence>(_ bytes: S) -> [InputEvent]
    where S.Element == UInt8 {
        var events: [InputEvent] = []

        for byte in bytes {
            let result = keyboardDecoder.feed(byte)
            switch result {
            case .pending:
                continue
            case .complete(let key):
                events.append(.key(key))
                return events
            case .invalid(let invalidBytes):
                events.append(.unknown(invalidBytes))
                return events
            }
        }

        return events
    }

    private mutating func resetRouting() {
        routeState = .ground
        buffer.removeAll(keepingCapacity: true)
        utf8Buffer.removeAll(keepingCapacity: true)
        utf8ExpectedBytes = 0
    }

    private static func csiKeyCode(for terminator: UInt8) -> UInt32? {
        switch terminator {
        case 0x41:
            return FunctionalKeyCode.up
        case 0x42:
            return FunctionalKeyCode.down
        case 0x43:
            return FunctionalKeyCode.right
        case 0x44:
            return FunctionalKeyCode.left
        case 0x46:
            return FunctionalKeyCode.end
        case 0x48:
            return FunctionalKeyCode.home
        case 0x50:
            return FunctionalKeyCode.f1
        case 0x51:
            return FunctionalKeyCode.f2
        case 0x52:
            return FunctionalKeyCode.f3
        case 0x53:
            return FunctionalKeyCode.f4
        default:
            return nil
        }
    }

    private static func csiTildeKeyCode(for parameter: Int) -> UInt32? {
        switch parameter {
        case 2:
            return FunctionalKeyCode.insert
        case 3:
            return FunctionalKeyCode.delete
        case 5:
            return FunctionalKeyCode.pageUp
        case 6:
            return FunctionalKeyCode.pageDown
        default:
            return nil
        }
    }

    private static func ss3KeyCode(for terminator: UInt8) -> UInt32? {
        switch terminator {
        case 0x50:
            return FunctionalKeyCode.f1
        case 0x51:
            return FunctionalKeyCode.f2
        case 0x52:
            return FunctionalKeyCode.f3
        case 0x53:
            return FunctionalKeyCode.f4
        default:
            return nil
        }
    }

    /// Parse the leading CSI numeric parameters directly from the routing buffer.
    private func parsedCSIParams() -> (firstParam: Int, modifier: Int, eventType: KeyEventType) {
        enum ParseField {
            case firstParam
            case modifier
            case eventType
        }

        var field = ParseField.firstParam
        var firstParam = 0
        var modifier = 1
        var eventTypeValue = 0

        parseLoop: for byte in buffer.dropFirst(2) {
            switch byte {
            case 0x30...0x39:
                switch field {
                case .firstParam:
                    guard Self.appendDigit(byte - 0x30, to: &firstParam, maximum: Int.max) else {
                        firstParam = Int.max
                        continue
                    }
                case .modifier:
                    guard Self.appendDigit(byte - 0x30, to: &modifier, maximum: Int.max) else {
                        modifier = Int.max
                        continue
                    }
                case .eventType:
                    guard Self.appendDigit(byte - 0x30, to: &eventTypeValue, maximum: Int.max)
                    else {
                        eventTypeValue = Int.max
                        continue
                    }
                }
            case 0x3b:
                guard case .firstParam = field else { break parseLoop }
                field = .modifier
            case 0x3a:
                guard case .modifier = field else { break parseLoop }
                field = .eventType
            default:
                break parseLoop
            }
        }

        let eventType = KeyEventType(rawValue: UInt8(clamping: eventTypeValue)) ?? .press
        return (firstParam, modifier, eventType)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
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
