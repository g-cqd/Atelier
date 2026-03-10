import Testing
@testable import KittyInput
@testable import KittyCodecs
@testable import KittyTerminal

@Suite("SequenceRouter")
struct SequenceRouterTests {
    @Test("Routes plain character to key event")
    func plainChar() {
        var router = SequenceRouter()
        let events = router.feed(0x61) // 'a'
        #expect(events.count == 1)
        if case .key(let key) = events.first {
            #expect(key.keyCode == 97)
        } else {
            Issue.record("Expected key event")
        }
    }

    @Test("Routes mouse sequence")
    func mouseSequence() {
        var router = SequenceRouter()
        // ESC [ < 0 ; 10 ; 5 M
        let bytes: [UInt8] = [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35, 0x4d]
        let events = router.feedAll(bytes)
        #expect(events.count == 1)
        if case .mouse(let mouse) = events.first {
            #expect(mouse.button == .left)
            #expect(mouse.col == 10)
            #expect(mouse.row == 5)
        } else {
            Issue.record("Expected mouse event")
        }
    }

    @Test("Routes focus events")
    func focusEvents() {
        var router = SequenceRouter()
        // CSI I = focus in
        let focusIn = router.feedAll([0x1b, 0x5b, 0x49])
        #expect(focusIn.count == 1)
        if case .focusIn = focusIn.first {} else {
            Issue.record("Expected focusIn")
        }

        // CSI O = focus out
        let focusOut = router.feedAll([0x1b, 0x5b, 0x4f])
        #expect(focusOut.count == 1)
        if case .focusOut = focusOut.first {} else {
            Issue.record("Expected focusOut")
        }
    }
}

@Suite("InputSource")
struct InputSourceTests {
    @Test("Reads events from mock connection")
    func readEvents() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x61]) // 'a'

        let source = InputSource(connection: mock)
        let task = source.start()

        var received: [InputEvent] = []
        for await event in source.events {
            received.append(event)
            break // just get one
        }

        task.cancel()
        #expect(received.count == 1)
    }
}
