/// Lines that lend their bytes (review §7.4, P1a): a text split into lines once, read a line at a time without making
/// strings. The lexers scan a line from it, and the diff reads its lines through it, so both apps share one shape:
/// GitDiffViewer's ``TextLines`` and KittyCode's ``Rope``.
public protocol LineSource: Sendable {
    var lineCount: Int { get }
    /// Lends the UTF-8 bytes of line `index`, without its terminator.
    /// - Precondition: `index` is in `0 ..< lineCount`.
    func withLineBytes<R, E: Error>(at index: Int, _ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R
}
