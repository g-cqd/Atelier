import Testing
@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal

@Suite("SequenceRouter")
struct SequenceRouterTests {
    private func makeSUT() -> SequenceRouter {
        SequenceRouter()
    }

    @Test("Routes plain character to key event")
    func plainChar() {
        var router = makeSUT()
        let events = router.feed(0x61)

        assertSingleKeyEvent(in: events, expectedKeyCode: 97)
    }

    @Test("Routes mouse sequence")
    func mouseSequence() {
        var router = makeSUT()
        let bytes: [UInt8] = [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35, 0x4d]
        let events = router.feedAll(bytes)

        #expect(events.count == 1)
        if case let .some(.mouse(mouse)) = events.first {
            #expect(mouse.button == .left)
            #expect(mouse.col == 10)
            #expect(mouse.row == 5)
        } else {
            Issue.record("Expected mouse event")
        }
    }

    @Test("Routes focus events")
    func focusEvents() {
        var router = makeSUT()

        let focusIn = router.feedAll([0x1b, 0x5b, 0x49])
        #expect(focusIn.count == 1)
        if case .some(.focusIn) = focusIn.first {} else {
            Issue.record("Expected focusIn")
        }

        let focusOut = router.feedAll([0x1b, 0x5b, 0x4f])
        #expect(focusOut.count == 1)
        if case .some(.focusOut) = focusOut.first {} else {
            Issue.record("Expected focusOut")
        }
    }

    @Test("Routes bracketed paste sequence")
    func bracketedPasteSequence() {
        var router = makeSUT()
        let bytes: [UInt8] = [
            0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e,
            0x68, 0x65, 0x6c, 0x6c, 0x6f,
            0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e,
        ]

        let events = router.feedAll(bytes)

        #expect(events.count == 1)
        if case let .some(.paste(text)) = events.first {
            #expect(text == "hello")
        } else {
            Issue.record("Expected paste event")
        }
    }

    @Test("Routes byte chunks without first copying into an array")
    func rawBufferInput() {
        var router = makeSUT()
        let bytes: [UInt8] = [0x1b, 0x5b, 0x49]
        let events = bytes.withUnsafeBytes { rawBytes in
            var routed: [InputEvent] = []
            router.feedAll(rawBytes, into: &routed)
            return routed
        }

        #expect(events.count == 1)
        if case .some(.focusIn) = events.first {} else {
            Issue.record("Expected focusIn")
        }
    }

    @Test("Routes standard CSI keys to functional key codes")
    func csiKeySequences() {
        func feed(_ bytes: [UInt8]) -> [InputEvent] {
            var r = makeSUT(); return r.feedAll(bytes)
        }
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x41]), expectedKeyCode: 57352)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x42]), expectedKeyCode: 57353)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x43]), expectedKeyCode: 57354)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x44]), expectedKeyCode: 57355)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x48]), expectedKeyCode: 57356)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x46]), expectedKeyCode: 57357)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x32, 0x7e]), expectedKeyCode: 57348)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x33, 0x7e]), expectedKeyCode: 57349)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x35, 0x7e]), expectedKeyCode: 57358)
        assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x36, 0x7e]), expectedKeyCode: 57359)
    }

    @Test("Routes SS3 function keys")
    func ss3FunctionKeySequences() {
        func feed(_ bytes: [UInt8]) -> [InputEvent] {
            var r = makeSUT(); return r.feedAll(bytes)
        }
        assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x50]), expectedKeyCode: 57364)
        assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x51]), expectedKeyCode: 57365)
        assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x52]), expectedKeyCode: 57366)
        assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x53]), expectedKeyCode: 57367)
    }

    @Test("Keeps CSI u keyboard decoding working")
    func csiUKeyboardSequence() {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x75])

        assertSingleKeyEvent(in: events, expectedKeyCode: 97)
    }

    @Test("Keeps CSI u modifier sequences intact until the terminating u")
    func csiUKeyboardSequenceWithModifiers() {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x32, 0x75])

        #expect(events.count == 1)
        if case let .some(.key(key)) = events.first {
            #expect(key.keyCode == 97)
            #expect(key.modifiers == .shift)
            #expect(key.eventType == .press)
        } else {
            Issue.record("Expected key event")
        }
    }

    @Test("Keeps CSI u alternate key fields intact until the terminating u")
    func csiUKeyboardSequenceWithAlternateKeys() {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x3a, 0x36, 0x35, 0x75])

        #expect(events.count == 1)
        if case let .some(.key(key)) = events.first {
            #expect(key.keyCode == 97)
            #expect(key.alternateKeys == [65])
            #expect(key.eventType == .press)
        } else {
            Issue.record("Expected key event")
        }
    }

    @Test("Treats overflowing CSI parameters as unknown without trapping")
    func overflowingCSIParameter() {
        var router = makeSUT()
        let bytes = Array("\u{1B}[999999999999999999999~".utf8)
        let events = router.feedAll(bytes)

        #expect(events.count == 1)
        if case let .some(.unknown(invalidBytes)) = events.first {
            #expect(invalidBytes == bytes)
        } else {
            Issue.record("Expected unknown event")
        }

        let recoveryEvents = router.feedAll([0x61])
        assertSingleKeyEvent(in: recoveryEvents, expectedKeyCode: 97)
    }

    private func assertSingleKeyEvent(in events: [InputEvent], expectedKeyCode: UInt32) {
        #expect(events.count == 1)
        if case let .some(.key(key)) = events.first {
            #expect(key.keyCode == expectedKeyCode)
            #expect(key.modifiers == [])
            #expect(key.eventType == .press)
        } else {
            Issue.record("Expected key event")
        }
    }
}

@Suite("InputSource")
struct InputSourceTests {
    @Test("Reads events from mock connection")
    func readEvents() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x61])

        let source = InputSource(connection: mock)
        let task = source.start()

        var received: [InputEvent] = []
        for await event in source.events {
            received.append(event)
            break
        }

        task.cancel()
        #expect(received.count == 1)
    }
}
