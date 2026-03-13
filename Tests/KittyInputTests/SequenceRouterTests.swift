import Darwin
import Testing

@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal

@Suite
struct SequenceRouterTests {
    private func makeSUT() -> SequenceRouter {
        SequenceRouter()
    }

    @Test
    func `Routes plain character to key event`() throws {
        var router = makeSUT()
        let events = router.feed(0x61)

        try assertSingleKeyEvent(in: events, expectedKeyCode: 97)
    }

    @Test
    func `Routes 4-byte UTF-8 text without truncating the scalar`() throws {
        var router = makeSUT()
        let events = router.feedAll(Array("😀".utf8))

        let key = try requireKeyEvent(events)
        #expect(key.keyCode == 0x1F600)
        #expect(key.modifiers == [])
        #expect(key.associatedText == "😀")
    }

    @Test
    func `Routes ESC-prefixed UTF-8 text as alt modified text`() throws {
        var router = makeSUT()
        let events = router.feedAll([0x1b] + Array("é".utf8))

        let key = try requireKeyEvent(events)
        #expect(key.keyCode == 0x00E9)
        #expect(key.modifiers == .alt)
        #expect(key.associatedText == "é")
    }

    @Test
    func `Routes mouse sequence`() throws {
        var router = makeSUT()
        let bytes: [UInt8] = [0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35, 0x4d]
        let events = router.feedAll(bytes)

        let mouse = try requireMouseEvent(events)
        #expect(mouse.button == .left)
        #expect(mouse.col == 10)
        #expect(mouse.row == 5)
    }

    @Test
    func `Routes focus events`() throws {
        var router = makeSUT()

        let focusIn = router.feedAll([0x1b, 0x5b, 0x49])
        _ = try requireFocusIn(focusIn)

        let focusOut = router.feedAll([0x1b, 0x5b, 0x4f])
        _ = try requireFocusOut(focusOut)
    }

    @Test
    func `Routes bracketed paste sequence`() throws {
        var router = makeSUT()
        let bytes: [UInt8] = [
            0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e,
            0x68, 0x65, 0x6c, 0x6c, 0x6f,
            0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e,
        ]

        let events = router.feedAll(bytes)

        #expect(try requirePasteEvent(events) == "hello")
    }

    @Test
    func `Routes byte chunks without first copying into an array`() throws {
        var router = makeSUT()
        let bytes: [UInt8] = [0x1b, 0x5b, 0x49]
        let events = bytes.withUnsafeBytes { rawBytes in
            var routed: [InputEvent] = []
            router.feedAll(rawBytes, into: &routed)
            return routed
        }

        _ = try requireFocusIn(events)
    }

    @Test
    func `Routes standard CSI keys to functional key codes`() throws {
        func feed(_ bytes: [UInt8]) -> [InputEvent] {
            var r = makeSUT()
            return r.feedAll(bytes)
        }
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x41]), expectedKeyCode: 57352)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x42]), expectedKeyCode: 57353)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x43]), expectedKeyCode: 57354)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x44]), expectedKeyCode: 57355)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x48]), expectedKeyCode: 57356)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x46]), expectedKeyCode: 57357)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x32, 0x7e]), expectedKeyCode: 57348)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x33, 0x7e]), expectedKeyCode: 57349)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x35, 0x7e]), expectedKeyCode: 57358)
        try assertSingleKeyEvent(in: feed([0x1b, 0x5b, 0x36, 0x7e]), expectedKeyCode: 57359)
    }

    @Test
    func `Routes SS3 function keys`() throws {
        func feed(_ bytes: [UInt8]) -> [InputEvent] {
            var r = makeSUT()
            return r.feedAll(bytes)
        }
        try assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x50]), expectedKeyCode: 57364)
        try assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x51]), expectedKeyCode: 57365)
        try assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x52]), expectedKeyCode: 57366)
        try assertSingleKeyEvent(in: feed([0x1b, 0x4f, 0x53]), expectedKeyCode: 57367)
    }

    @Test
    func `Keeps CSI u keyboard decoding working`() throws {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x75])

        try assertSingleKeyEvent(in: events, expectedKeyCode: 97)
    }

    @Test
    func `Keeps CSI u modifier sequences intact until the terminating u`() throws {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x32, 0x75])

        let key = try requireKeyEvent(events)
        #expect(key.keyCode == 97)
        #expect(key.modifiers == .shift)
        #expect(key.eventType == .press)
    }

    @Test
    func `Keeps CSI u alternate key fields intact until the terminating u`() throws {
        var router = makeSUT()
        let events = router.feedAll([0x1b, 0x5b, 0x39, 0x37, 0x3a, 0x36, 0x35, 0x75])

        let key = try requireKeyEvent(events)
        #expect(key.keyCode == 97)
        #expect(key.alternateKeys == [65])
        #expect(key.eventType == .press)
    }

    @Test
    func `Treats overflowing CSI parameters as unknown without trapping`() throws {
        var router = makeSUT()
        let bytes = Array("\u{1B}[999999999999999999999~".utf8)
        let events = router.feedAll(bytes)

        #expect(try requireUnknownEvent(events) == bytes)

        let recoveryEvents = router.feedAll([0x61])
        try assertSingleKeyEvent(in: recoveryEvents, expectedKeyCode: 97)
    }

    @Test
    func `Routes mouse drag sequence button-event tracking`() throws {
        var router = makeSUT()

        // Press: CSI < 0 ; 10 ; 5 M (left press at col 10, row 5)
        let press = router.feedAll([0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x35, 0x4d])
        let pressEvent = try requireMouseEvent(press)
        #expect(pressEvent.button == .left)
        #expect(pressEvent.kind == .press)
        #expect(pressEvent.col == 10)
        #expect(pressEvent.row == 5)

        // Drag: CSI < 32 ; 10 ; 8 M (left drag to col 10, row 8)
        let drag = router.feedAll([
            0x1b, 0x5b, 0x3c, 0x33, 0x32, 0x3b, 0x31, 0x30, 0x3b, 0x38, 0x4d,
        ])
        let dragEvent = try requireMouseEvent(drag)
        #expect(dragEvent.button == .left)
        #expect(dragEvent.kind == .drag)
        #expect(dragEvent.col == 10)
        #expect(dragEvent.row == 8)

        // Release: CSI < 0 ; 10 ; 8 m (left release at col 10, row 8)
        let release = router.feedAll([0x1b, 0x5b, 0x3c, 0x30, 0x3b, 0x31, 0x30, 0x3b, 0x38, 0x6d])
        let releaseEvent = try requireMouseEvent(release)
        #expect(releaseEvent.button == .left)
        #expect(releaseEvent.kind == .release)
        #expect(releaseEvent.col == 10)
        #expect(releaseEvent.row == 8)
    }

    private func assertSingleKeyEvent(in events: [InputEvent], expectedKeyCode: UInt32) throws {
        let key = try requireKeyEvent(events)
        #expect(key.keyCode == expectedKeyCode)
        #expect(key.modifiers == [])
        #expect(key.eventType == .press)
    }
}
