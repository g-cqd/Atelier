import Testing
@testable import KittyTerminal

@Suite("Terminal Types")
struct TerminalTypesTests {
    @Test("TerminalSize equality")
    func terminalSizeEquality() {
        let a = TerminalSize(columns: 80, rows: 24)
        let b = TerminalSize(columns: 80, rows: 24)
        #expect(a == b)
    }

    @Test("TerminalSize with pixel dimensions")
    func terminalSizePixels() {
        let size = TerminalSize(columns: 120, rows: 40, pixelWidth: 1920, pixelHeight: 1080)
        #expect(size.columns == 120)
        #expect(size.pixelWidth == 1920)
    }
}

@Suite("MockTerminalConnection")
struct MockTerminalConnectionTests {
    @Test("Read returns fed input")
    func readInput() throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x41, 0x42, 0x43])

        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 16, alignment: 1)
        defer { buffer.deallocate() }

        let count = try mock.read(into: buffer)
        #expect(count == 3)
        #expect(buffer[0] == 0x41)
        #expect(buffer[1] == 0x42)
        #expect(buffer[2] == 0x43)
    }

    @Test("Write accumulates output")
    func writeOutput() throws {
        let mock = MockTerminalConnection()
        try mock.write([0x1b, 0x5b, 0x48])
        #expect(mock.writtenOutput == [0x1b, 0x5b, 0x48])
    }

    @Test("Raw mode tracking")
    func rawModeTracking() throws {
        let mock = MockTerminalConnection()
        #expect(!mock.isRawMode)
        try mock.enterRawMode()
        #expect(mock.isRawMode)
        #expect(mock.enterRawModeCallCount == 1)
        try mock.restoreMode()
        #expect(!mock.isRawMode)
        #expect(mock.restoreModeCallCount == 1)
    }

    @Test("Read throws on empty buffer")
    func readEmpty() {
        let mock = MockTerminalConnection()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 16, alignment: 1)
        defer { buffer.deallocate() }

        #expect(throws: TerminalError.connectionClosed) {
            try mock.read(into: buffer)
        }
    }

    @Test("RawModeGuard enters and restores")
    func rawModeGuard() throws {
        let mock = MockTerminalConnection()
        do {
            let _guard = try RawModeGuard(connection: mock)
            #expect(mock.isRawMode)
            _ = _guard
        }
        #expect(!mock.isRawMode)
        #expect(mock.enterRawModeCallCount == 1)
        #expect(mock.restoreModeCallCount == 1)
    }
}
