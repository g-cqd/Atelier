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

    @Test
    func `A lone ESC that ends a read arrives as the Escape key`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x1B])
        let source = InputSource(connection: mock)
        let task = source.start()
        defer { task.cancel() }

        // The mock has nothing more after the first read, so the stream finishes.
        var events: [InputEvent] = []
        for await event in source.events {
            events.append(event)
        }

        let key = try requireKeyEvent(events)
        #expect(key.keyCode == 0x1B)
        #expect(key.modifiers == [])
    }

    @Test
    func `An ESC that ends a full read waits for the rest of its sequence in the next read`() async throws {
        let mock = MockTerminalConnection()
        let plainKeys = [UInt8](repeating: 0x61, count: InputSource.readSize - 1)
        mock.feedInput(plainKeys + [0x1B, 0x5B, 0x41])
        let source = InputSource(connection: mock)
        let task = source.start()
        defer { task.cancel() }

        var keyCodes: [UInt32] = []
        for await event in source.events {
            guard case .key(let key) = event else { continue }
            keyCodes.append(key.keyCode)
        }

        #expect(keyCodes == [UInt32](repeating: 0x61, count: plainKeys.count) + [57352])
    }
}
