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

    private static let maxPasteSize = 1_048_576  // 1MB

    private var keyboardDecoder = KeyboardDecoder()
    private var mouseDecoder = MouseDecoder()
    private var buffer: [UInt8] = []
    private var routeState: RouteState = .ground

    public init() {}

    public mutating func feed(_ byte: UInt8) -> [InputEvent] {
        var events: [InputEvent] = []

        switch routeState {
        case .ground:
            if byte == 0x1b {
                routeState = .escape
                buffer = [byte]
            } else if case .complete(let key) = keyboardDecoder.feed(byte) {
                events.append(.key(key))
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
            case 0x30 ... 0x39:
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
            let firstParam = parsed.params.first ?? 0
            let modifierByte = parsed.params.count >= 2 ? parsed.params[1] : 1
            let mods = KeyModifiers(rawValue: UInt8(max(0, modifierByte - 1)))
            let eventType = parsed.eventType

            switch byte {
            case 0x7e:
                if firstParam == 200 {
                    routeState = .paste
                    buffer.removeAll(keepingCapacity: true)
                } else if let keyCode = Self.csiTildeKeyCode(for: firstParam) {
                    events.append(.key(KeyEvent(keyCode: keyCode, modifiers: mods, eventType: eventType)))
                    resetRouting()
                } else {
                    events.append(.unknown(buffer))
                    resetRouting()
                }
            default:
                if let keyCode = Self.csiKeyCode(for: byte) {
                    events.append(.key(KeyEvent(keyCode: keyCode, modifiers: mods, eventType: eventType)))
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
                events.append(.unknown(Array("osc overflow".utf8)))
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
                events.append(.unknown(Array("paste overflow".utf8)))
                resetRouting()
            } else if buffer.count >= Self.pasteEndMarker.count,
               buffer.suffix(Self.pasteEndMarker.count).elementsEqual(Self.pasteEndMarker) {
                let pasteBytes = Array(buffer.dropLast(Self.pasteEndMarker.count))
                let text = String(bytes: pasteBytes, encoding: .utf8) ?? ""
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
                events.append(contentsOf: feed(byte))
            }
        }

        return events
    }

    /// Feed a chunk of bytes and collect all emitted events.
    public mutating func feedAll(_ bytes: [UInt8]) -> [InputEvent] {
        var events: [InputEvent] = []
        for byte in bytes {
            events.append(contentsOf: feed(byte))
        }
        return events
    }

    private mutating func decodeKeyboardSequence(_ bytes: [UInt8]) -> [InputEvent] {
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

    /// Parse all semicolon-separated numeric parameters from the current CSI buffer.
    /// Skips the leading ESC [ prefix.
    /// Returns (semicolonParams, eventType). The modifier field may contain
    /// a colon-separated event type (e.g. `1;3:3A` → modifier=3, eventType=release).
    /// Colons within the second field are parsed as sub-fields, not top-level separators.
    private func parsedCSIParams() -> (params: [Int], eventType: KeyEventType) {
        // Split by ';' first, keeping raw bytes per field
        var fields: [[UInt8]] = [[]]
        for byte in buffer.dropFirst(2) {
            if byte == 0x3b { // ;
                fields.append([])
            } else if Self.isDigit(byte) || byte == 0x3a { // digit or :
                fields[fields.count - 1].append(byte)
            } else {
                break // terminator
            }
        }

        // Parse first field as a plain number
        let firstParam = fields.isEmpty ? 0 : Self.parseNumberFromBytes(fields[0])

        // Parse second field: may be "modifier" or "modifier:eventType"
        var modValue = 1
        var eventType: KeyEventType = .press
        if fields.count >= 2 {
            let modField = fields[1]
            if let colonIdx = modField.firstIndex(of: 0x3a) {
                modValue = Self.parseNumberFromBytes(Array(modField[..<colonIdx]))
                let evtValue = Self.parseNumberFromBytes(Array(modField[(colonIdx + 1)...]))
                eventType = KeyEventType(rawValue: UInt8(evtValue)) ?? .press
            } else {
                modValue = Self.parseNumberFromBytes(modField)
            }
        }

        return (params: [firstParam, modValue], eventType: eventType)
    }

    private static func parseNumberFromBytes(_ bytes: [UInt8]) -> Int {
        var value = 0
        for byte in bytes where isDigit(byte) {
            let (multiplied, overflow1) = value.multipliedReportingOverflow(by: 10)
            let (added, overflow2) = multiplied.addingReportingOverflow(Int(byte - 0x30))
            if overflow1 || overflow2 { return Int.max }
            value = added
        }
        return value
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
