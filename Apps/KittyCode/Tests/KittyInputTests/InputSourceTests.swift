import Darwin
import Testing

@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal

@Suite
struct InputSourceTests {
    @Test
    func `Reads events from mock connection`() async throws {
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

    @Test
    func `Start continues after interrupted reads and preserves subsequent input`() async throws {
        let mock = MockTerminalConnection()
        mock.enqueueReadError(.readFailed(EINTR))
        mock.feedInput([0x61])

        let source = InputSource(connection: mock)
        let task = source.start()
        defer { task.cancel() }

        var iterator = source.events.makeAsyncIterator()
        let event = await iterator.next()
        let key = try requireKeyEvent(event)
        #expect(key.keyCode == 97)
        #expect(key.modifiers == [])
        #expect(key.eventType == .press)
    }
}
