import Testing

@testable import KittyCodecs
@testable import KittyInput

/// A paste, an OSC or a control sequence past its cap is dropped up to its own end, so no byte of its tail is typed,
/// and the input after that end routes as usual.
@Suite
struct SequenceRouterOverflowTests {
    /// 1.5 MiB, half again the paste and OSC cap.
    private static let oversizedPayloadCount = 1_572_864

    /// Expects `b` to be the only key in `events`. Counts rather than compares arrays: a failure would otherwise diff
    /// hundreds of thousands of stray keys.
    private func expectOnlyKeyB(in events: [InputEvent], sourceLocation: SourceLocation = #_sourceLocation) {
        let keyCodes = events.compactMap { event -> UInt32? in
            guard case .key(let key) = event else { return nil }
            return key.keyCode
        }
        #expect(keyCodes.count == 1, "\(keyCodes.count) keys typed", sourceLocation: sourceLocation)
        #expect(keyCodes.last == 0x62, sourceLocation: sourceLocation)
    }

    /// The overflow events in `events`.
    private func overflows(_ events: [InputEvent]) -> [InputOverflow] {
        events.compactMap { event in
            guard case .overflow(let overflow) = event else { return nil }
            return overflow
        }
    }

    @Test
    func `A paste over the cap reports one paste overflow`() {
        var router = SequenceRouter()
        let body = [UInt8](repeating: 0x61, count: Self.oversizedPayloadCount)

        let events = router.feedAll(Array("\u{1B}[200~".utf8) + body + Array("\u{1B}[201~".utf8))

        #expect(overflows(events) == [.paste])
    }

    @Test
    func `An OSC over the cap reports one overflow carrying its command number`() {
        var router = SequenceRouter()
        let payload = [UInt8](repeating: 0x41, count: Self.oversizedPayloadCount)

        let events = router.feedAll(Array("\u{1B}]52;c;".utf8) + payload + [0x07])

        #expect(overflows(events) == [.osc(command: 52)])
    }

    /// The overflow lands on the end marker's first byte, so the rest of the marker must still end the paste.
    @Test
    func `A paste whose end marker straddles the cap still ends at that marker`() {
        var router = SequenceRouter()
        let body = [UInt8](repeating: 0x61, count: SequenceRouter.maxPasteSize)
        let bytes = Array("\u{1B}[200~".utf8) + body + Array("\u{1B}[201~b".utf8)

        expectOnlyKeyB(in: router.feedAll(bytes))
    }

    @Test
    func `A paste over the cap types none of its tail, and the key after its end marker arrives`() {
        var router = SequenceRouter()
        let body = [UInt8](repeating: 0x61, count: Self.oversizedPayloadCount)
        let bytes = Array("\u{1B}[200~".utf8) + body + Array("\u{1B}[201~b".utf8)

        expectOnlyKeyB(in: router.feedAll(bytes))
    }

    @Test(arguments: ["\u{07}", "\u{1B}\\"])
    func `An OSC over the cap types none of its tail, and the key after its terminator arrives`(
        terminator: String
    ) {
        var router = SequenceRouter()
        let payload = [UInt8](repeating: 0x41, count: Self.oversizedPayloadCount)
        let bytes = Array("\u{1B}]52;c;".utf8) + payload + Array((terminator + "b").utf8)

        expectOnlyKeyB(in: router.feedAll(bytes))
    }

    /// A private-mode reply and a key sequence whose parameters run past the 4 KiB control-sequence cap.
    @Test(arguments: [("\u{1B}[?", "c"), ("\u{1B}[", "~")])
    func `A control sequence over the cap types none of its tail, and the key after its final byte arrives`(
        introducer: String, finalByte: String
    ) {
        var router = SequenceRouter()
        let parameters = String(repeating: "1;", count: 3000)
        let bytes = Array((introducer + parameters + finalByte + "b").utf8)

        expectOnlyKeyB(in: router.feedAll(bytes))
    }
}
