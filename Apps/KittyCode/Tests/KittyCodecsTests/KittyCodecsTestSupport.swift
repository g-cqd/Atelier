import Testing

@testable import KittyCodecs

func feedKeyboard(_ sequence: String, into decoder: inout KeyboardDecoder) -> DecoderResult<
    KeyEvent
> {
    var result: DecoderResult<KeyEvent> = .pending
    for byte in sequence.utf8 {
        result = decoder.feed(byte)
        switch result {
            case .pending:
                continue
            case .complete, .invalid:
                return result
        }
    }
    return result
}

func feedMouse(_ sequence: String, into decoder: inout MouseDecoder) -> DecoderResult<
    MouseEvent
> {
    var result: DecoderResult<MouseEvent> = .pending
    for byte in sequence.utf8 {
        result = decoder.feed(byte)
        switch result {
            case .pending:
                continue
            case .complete, .invalid:
                return result
        }
    }
    return result
}

enum DecoderExpectationError: Error {
    case expectedCompleteKeyboardEvent
    case expectedCompleteMouseEvent
}

func requireCompletedKeyboardEvent(_ result: DecoderResult<KeyEvent>) throws -> KeyEvent {
    guard case .complete(let event) = result else {
        throw DecoderExpectationError.expectedCompleteKeyboardEvent
    }
    return event
}

func requireCompletedMouseEvent(_ result: DecoderResult<MouseEvent>) throws -> MouseEvent {
    guard case .complete(let event) = result else {
        throw DecoderExpectationError.expectedCompleteMouseEvent
    }
    return event
}
