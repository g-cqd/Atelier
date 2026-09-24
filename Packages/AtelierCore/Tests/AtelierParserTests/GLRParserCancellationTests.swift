import Synchronization
import Testing

@testable import AtelierGrammar
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
    func `A parse of comments alone stops at a cancellation check`() throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        var checks = 0

        #expect(throws: ParseError.cancelled(atToken: GLRParser.cancellationCheckInterval)) {
            // Cancelled from the second check on, which only a check on comments, 256 tokens in, reaches.
            try parser.parse(
                String(repeating: "// comment\n", count: 600),
                externalScanner: nil,
                isCancelled: {
                    checks += 1
                    return checks > 1
                })
        }
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
    func `A cancelled parse does not call the external scanner`() throws {
        let grammar = GrammarDefinition(
            name: "cancelled_scan",
            rules: [("source", .choice([.symbol("counted"), .string("x")]))],
            extras: [], externals: [.symbol("counted")])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let scanner = CountingScanner()

        #expect(throws: ParseError.cancelled(atToken: 0)) {
            try parser.parse("x", externalScanner: scanner, isCancelled: { true })
        }
        #expect(scanner.scans == 0)
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
private final class CountingScanner: GrammarExternalScanner {
    private let count = Mutex(0)

    var scans: Int { count.withLock { $0 } }

    static let externalNames = ["counted"]

    required init() {}

    func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        count.withLock { $0 += 1 }
        return false
    }

    func serialize(into buffer: inout [UInt8]) {}
    func deserialize(_ state: ArraySlice<UInt8>) {}
}
