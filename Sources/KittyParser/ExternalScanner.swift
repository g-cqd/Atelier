/// Protocol for custom lexer extensions using Swift closures.
///
/// Some grammars need context-dependent tokenization that can't be expressed
/// in the grammar.json format (e.g., Python indentation, heredocs).
public protocol ExternalScanner: Sendable {
    /// The token types this scanner can produce.
    var validSymbols: [String] { get }

    /// Attempt to scan a token at the current position.
    /// Returns the token type and number of bytes consumed, or nil if no match.
    func scan(
        source: UnsafeBufferPointer<UInt8>,
        position: Int,
        validSymbols: Set<String>
    ) -> (type: String, length: Int)?
}

/// A no-op external scanner for grammars that don't need custom lexing.
public struct NullExternalScanner: ExternalScanner, Sendable {
    public var validSymbols: [String] { [] }

    public init() {}

    public func scan(
        source: UnsafeBufferPointer<UInt8>,
        position: Int,
        validSymbols: Set<String>
    ) -> (type: String, length: Int)? {
        nil
    }
}
