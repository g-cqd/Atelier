import Synchronization
import Testing

@testable import AtelierParser

@Suite
struct GLRParserCancellationTests {
    /// 6,000 tokens, enough for many cancellation checks.
    private static let source = String(repeating: "[", count: 3_000) + String(repeating: "]", count: 3_000)

    @Test
    func `A parse cancelled mid-file stops at the next check`() throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        var checks = 0

        #expect(throws: ParseError.cancelled(atToken: GLRParser.cancellationCheckInterval)) {
            // Cancelled from the second check on: the parse has passed its first check, at token 0, when it happens.
            try parser.parse(
                Self.source,
                externalScanner: nil,
                isCancelled: {
                    checks += 1
                    return checks > 1
                })
        }
        #expect(checks == 2)
    }

    @Test
    func `A parse in a cancelled task stops before its first token`() async throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)

        let error = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return Self.parseError(parser)
        }
        .value

        #expect(error == .cancelled(atToken: 0))
    }

    @Test
    func `A parse cancelled at its first check has read only the first token`() throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        let scanner = CountingScanner()

        #expect(throws: ParseError.cancelled(atToken: 0)) {
            // Strings of three letters: a lexer that reads the whole source first asks the scanner 9,000 times.
            try parser.parse(
                String(repeating: #""abc" "#, count: 3_000), externalScanner: scanner, isCancelled: { true })
        }
        #expect(scanner.scans == 1)
    }

    private static func parseError(_ parser: GLRParser) -> ParseError? {
        do {
            _ = try parser.parse(source)
            return nil
        } catch {
            return error
        }
    }
}

/// An external scanner that finds nothing and counts how often the lexer asks it: once for each token it reads.
private final class CountingScanner: ExternalScanner {
    private let count = Mutex(0)

    var scans: Int { count.withLock { $0 } }

    var validSymbols: [String] { ["counted"] }

    func scan(
        source: UnsafeBufferPointer<UInt8>,
        position: Int,
        validSymbols: Set<String>
    ) -> (type: String, length: Int)? {
        count.withLock { $0 += 1 }
        return nil
    }
}
