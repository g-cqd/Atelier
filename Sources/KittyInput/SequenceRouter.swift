import KittyCodecs

/// Routes incoming byte sequences to appropriate decoders based on prefix.
public struct SequenceRouter: Sendable {
    private var keyboardDecoder = KeyboardDecoder()
    private var mouseDecoder = MouseDecoder()
    private var buffer: [UInt8] = []
    private var routeState: RouteState = .ground

    private enum RouteState: Sendable {
        case ground
        case escape
        case csi
        case csiLt       // CSI < — mouse
        case csiGt       // CSI > — keyboard mode response
        case keyboard     // CSI ... u
        case mouse        // CSI < ... M/m
        case osc          // ESC ]
        case paste        // bracketed paste content
        case focusEvent   // CSI I / CSI O
    }

    public init() {}

    public mutating func feed(_ byte: UInt8) -> [InputEvent] {
        var events: [InputEvent] = []

        switch routeState {
        case .ground:
            if byte == 0x1b {
                routeState = .escape
                buffer = [byte]
            } else {
                // Plain character — route through keyboard decoder
                if case .complete(let key) = keyboardDecoder.feed(byte) {
                    events.append(.key(key))
                }
            }

        case .escape:
            buffer.append(byte)
            if byte == 0x5b { // [
                routeState = .csi
            } else if byte == 0x5d { // ]
                routeState = .osc
            } else if byte == 0x4f { // O — SS3 (function keys)
                routeState = .keyboard
                // Re-feed the buffered bytes to keyboard decoder
                for b in buffer {
                    _ = keyboardDecoder.feed(b)
                }
            } else {
                // ESC + char — feed to keyboard decoder
                for b in buffer {
                    if case .complete(let key) = keyboardDecoder.feed(b) {
                        events.append(.key(key))
                    }
                }
                routeState = .ground
                buffer.removeAll()
            }

        case .csi:
            buffer.append(byte)
            if byte == 0x3c { // <
                routeState = .csiLt
            } else if byte == 0x3e { // >
                routeState = .csiGt
            } else if byte == 0x49 { // I — focus in
                events.append(.focusIn)
                routeState = .ground
                buffer.removeAll()
            } else if byte == 0x4f { // O — focus out
                events.append(.focusOut)
                routeState = .ground
                buffer.removeAll()
            } else {
                // Route to keyboard decoder
                routeState = .keyboard
                for b in buffer {
                    _ = keyboardDecoder.feed(b)
                }
            }

        case .csiLt:
            buffer.append(byte)
            // This is a mouse sequence — route remaining bytes to mouse decoder
            routeState = .mouse
            for b in buffer {
                _ = mouseDecoder.feed(b)
            }

        case .csiGt:
            buffer.append(byte)
            // Keyboard mode response or push — route to keyboard decoder
            routeState = .keyboard
            for b in buffer {
                _ = keyboardDecoder.feed(b)
            }

        case .keyboard:
            let result = keyboardDecoder.feed(byte)
            switch result {
            case .complete(let key):
                events.append(.key(key))
                routeState = .ground
                buffer.removeAll()
            case .invalid(let bytes):
                events.append(.unknown(bytes))
                routeState = .ground
                buffer.removeAll()
            case .pending:
                break
            }

        case .mouse:
            let result = mouseDecoder.feed(byte)
            switch result {
            case .complete(let mouse):
                events.append(.mouse(mouse))
                routeState = .ground
                buffer.removeAll()
            case .invalid(let bytes):
                events.append(.unknown(bytes))
                routeState = .ground
                buffer.removeAll()
            case .pending:
                break
            }

        case .osc:
            buffer.append(byte)
            // OSC sequences end with ST (ESC \) or BEL (0x07)
            if byte == 0x07 {
                events.append(.unknown(buffer))
                routeState = .ground
                buffer.removeAll()
            } else if buffer.count >= 2 && buffer[buffer.count - 2] == 0x1b && byte == 0x5c {
                events.append(.unknown(buffer))
                routeState = .ground
                buffer.removeAll()
            }

        case .paste:
            buffer.append(byte)
            // Check for paste end: ESC [ 2 0 1 ~
            if buffer.count >= 6 {
                let tail = buffer.suffix(6)
                if tail.elementsEqual([0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e]) {
                    let pasteBytes = Array(buffer.dropLast(6))
                    let text = String(bytes: pasteBytes, encoding: .utf8) ?? ""
                    events.append(.paste(text))
                    routeState = .ground
                    buffer.removeAll()
                }
            }

        case .focusEvent:
            break
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
}
