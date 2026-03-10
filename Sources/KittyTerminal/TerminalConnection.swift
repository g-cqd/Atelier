public protocol TerminalConnection: Sendable {
    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int
    func write(_ bytes: [UInt8]) throws(TerminalError)
    func enterRawMode() throws(TerminalError)
    func restoreMode() throws(TerminalError)
    func getSize() throws(TerminalError) -> TerminalSize
}
