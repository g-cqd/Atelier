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

    /// The paste bodies each chunk split below is tried on: plain text, and text holding starts of the end marker
    /// that a later byte breaks off.
    private static let pasteBodies = ["hello", "a\u{1B}[20x", "\u{1B}[2\u{1B}[201", "\u{1B}\u{1B}[201]"]

    @Test(arguments: pasteBodies)
    func `A paste ends at its end marker wherever the reads split it`(body: String) throws {
        let input = Array("\u{1B}[200~\(body)\u{1B}[201~b".utf8)
        for split in 1 ..< input.count {
            var router = makeSUT()

            let events = router.feedAll(Array(input[..<split])) + router.feedAll(Array(input[split...]))

            let pastes = events.compactMap { event -> String? in
                guard case .paste(let text) = event else { return nil }
                return text
            }
            #expect(pastes == [body], "split at \(split)")
            guard case .key(let key) = events.last else {
                Issue.record("split at \(split): the byte after the marker is not a key")
                continue
            }
            #expect(key.keyCode == 0x62, "split at \(split)")
        }
    }

    @Test
    func `Routes bracketed paste sequence`() throws {
        var router = makeSUT()
        let bytes: [UInt8] = [
            0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e,
            0x68, 0x65, 0x6c, 0x6c, 0x6f,
            0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e
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
            0x1b, 0x5b, 0x3c, 0x33, 0x32, 0x3b, 0x31, 0x30, 0x3b, 0x38, 0x4d
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

    /// The device-attributes reply that ends the palette query, a mode report and a keyboard-flags report.
    @Test(arguments: ["\u{1B}[?62;22c", "\u{1B}[?2026;2$y", "\u{1B}[?31u"])
    func `A private-mode reply arrives whole, with no key events`(reply: String) throws {
        var router = makeSUT()
        let bytes = Array(reply.utf8)

        #expect(try requireUnknownEvent(router.feedAll(bytes)) == bytes)
    }

    @Test
    func `A private-mode reply cut short by a new sequence leaves that sequence intact`() throws {
        var router = makeSUT()
        let events = router.feedAll(Array("\u{1B}[?62\u{1B}[A".utf8))

        try #require(events.count == 2)
        #expect(try requireUnknownEvent([events[0]]) == Array("\u{1B}[?62".utf8))
        try assertSingleKeyEvent(in: [events[1]], expectedKeyCode: 57352)
    }

    @Test
    func `A lone ESC at the end of a read is Escape, and the next read's key carries no Alt`() throws {
        var router = makeSUT()
        var events: [InputEvent] = []
        [UInt8]([0x1B]).withUnsafeBytes { router.feedAll($0, into: &events) }
        router.flushPendingEscape(into: &events)

        try assertSingleKeyEvent(in: events, expectedKeyCode: 0x1B)
        try assertSingleKeyEvent(in: router.feedAll([0x6A]), expectedKeyCode: 0x6A)
    }

    @Test
    func `The end of a read leaves a sequence past its ESC pending`() throws {
        var router = makeSUT()
        var events: [InputEvent] = []
        [UInt8]([0x1B, 0x5B]).withUnsafeBytes { router.feedAll($0, into: &events) }
        router.flushPendingEscape(into: &events)

        #expect(events.isEmpty)
        try assertSingleKeyEvent(in: router.feedAll([0x41]), expectedKeyCode: 57352)
    }

    @Test
    func `A stray lead byte before an arrow key yields a replacement character, then the arrow`() throws {
        var router = makeSUT()
        let events = router.feedAll([0xC3, 0x1B, 0x5B, 0x41])

        try #require(events.count == 2)
        let replacement = try requireKeyEvent(events[0])
        #expect(replacement.keyCode == 0xFFFD)
        #expect(replacement.associatedText == "\u{FFFD}")
        try assertSingleKeyEvent(in: [events[1]], expectedKeyCode: 57352)
    }

    @Test
    func `A paste with an invalid byte keeps its text around a replacement character`() throws {
        var router = makeSUT()
        let bytes = Array("\u{1B}[200~ab".utf8) + [0xFF] + Array("cd\u{1B}[201~".utf8)

        #expect(try requirePasteEvent(router.feedAll(bytes)) == "ab\u{FFFD}cd")
    }

    private func assertSingleKeyEvent(in events: [InputEvent], expectedKeyCode: UInt32) throws {
        let key = try requireKeyEvent(events)
        #expect(key.keyCode == expectedKeyCode)
        #expect(key.modifiers == [])
        #expect(key.eventType == .press)
    }

    // MARK: - Control-sequence overflow caps

    /// An endless `ESC [` parameter stream hits the 4096-byte cap, which reports one control-sequence overflow.
    @Test
    func `csiParam overflow reports one control-sequence overflow`() throws {
        var router = makeSUT()
        var events = router.feedAll([0x1b, 0x5b])  // ESC [
        let pattern: [UInt8] = [0x33, 0x3b]  // "3;" repeated
        for _ in 0 ..< 3000 {
            events.append(contentsOf: router.feed(pattern[0]))
            events.append(contentsOf: router.feed(pattern[1]))
        }
        let overflows = events.filter { event in
            if case .overflow(.controlSequence) = event { return true }
            return false
        }
        #expect(overflows.count == 1)
    }

    /// OSC keeps its own 1 MB cap for title-sized payloads, so 5000 bytes inside one are no control overflow.
    @Test
    func `osc state is not subject to the smaller control-sequence cap`() throws {
        var router = makeSUT()
        let osc: [UInt8] = [0x1b, 0x5d] + [UInt8](repeating: 0x33, count: 5000) + [0x07]  // ESC ] … BEL

        #expect(try requireUnknownEvent(router.feedAll(osc)) == osc)
    }
}
