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

    private static func parseError(_ parser: GLRParser) -> ParseError? {
        do {
            _ = try parser.parse(source)
            return nil
        } catch {
            return error
        }
    }
}
