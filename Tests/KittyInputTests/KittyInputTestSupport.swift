import Darwin
import Testing

@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal

enum InputEventExpectationError: Error {
    case expectedFocusIn
    case expectedFocusOut
    case expectedKeyEvent
    case expectedMouseEvent
    case expectedPasteEvent
    case expectedUnknownEvent
}

func requireFocusIn(_ events: [InputEvent]) throws {
    #expect(events.count == 1)
    let event = try #require(events.onlyElement)
    guard case .focusIn = event else {
        throw InputEventExpectationError.expectedFocusIn
    }
}

func requireFocusOut(_ events: [InputEvent]) throws {
    #expect(events.count == 1)
    let event = try #require(events.onlyElement)
    guard case .focusOut = event else {
        throw InputEventExpectationError.expectedFocusOut
    }
}

func requireKeyEvent(_ events: [InputEvent]) throws -> KeyEvent {
    #expect(events.count == 1)
    return try requireKeyEvent(events.onlyElement)
}

func requireKeyEvent(_ event: InputEvent?) throws -> KeyEvent {
    guard case .some(.key(let key)) = event else {
        throw InputEventExpectationError.expectedKeyEvent
    }
    return key
}

func requireMouseEvent(_ events: [InputEvent]) throws -> MouseEvent {
    #expect(events.count == 1)
    let event = try #require(events.onlyElement)
    guard case .mouse(let mouse) = event else {
        throw InputEventExpectationError.expectedMouseEvent
    }
    return mouse
}

func requirePasteEvent(_ events: [InputEvent]) throws -> String {
    #expect(events.count == 1)
    let event = try #require(events.onlyElement)
    guard case .paste(let text) = event else {
        throw InputEventExpectationError.expectedPasteEvent
    }
    return text
}

func requireUnknownEvent(_ events: [InputEvent]) throws -> [UInt8] {
    #expect(events.count == 1)
    let event = try #require(events.onlyElement)
    guard case .unknown(let bytes) = event else {
        throw InputEventExpectationError.expectedUnknownEvent
    }
    return bytes
}

extension Collection {
    fileprivate var onlyElement: Element? {
        guard count == 1 else { return nil }
        return first
    }
}
