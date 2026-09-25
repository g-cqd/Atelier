import AtelierLexers
import AtelierSyntaxModel
import AtelierText
import Synchronization
import Testing

/// Lexing visible lines first, then the rest (P1a), as tier 0 of the tier job.
struct ProgressiveHighlightingTests {
    /// What a run emitted, in order.
    private final class Emitted: Sendable {
        private let chunks = Mutex<[(lines: Range<Int>, tokens: LineTokens)]>([])

        func record(_ lines: Range<Int>, _ tokens: LineTokens) {
            chunks.withLock { $0.append((lines, tokens)) }
        }

        var order: [Range<Int>] { chunks.withLock { $0.map(\.lines) } }

        /// Each line's tokens as the consumer ends up with them: the last chunk that covered the line wins.
        func landed(lineCount: Int) -> [[LineToken]?] {
            var lines = [[LineToken]?](repeating: nil, count: lineCount)
            for chunk in chunks.withLock({ $0 }) {
                for (offset, line) in chunk.lines.enumerated() { lines[line] = Array(chunk.tokens[offset]) }
            }
            return lines
        }
    }

    /// 2,000 lines of Swift, with a block comment that opens at line 950 and closes at line 1,020.
    private static let text: String = {
        var lines = (0 ..< 2_000).map { "let value\($0) = \"text\" // note" }
        lines[950] = "/* a comment that runs on"
        lines[1_020] = "still the comment */ let after = 1"
        return lines.joined(separator: "\n") + "\n"
    }()

    private static let lexer = LexicalLineLexer(language: .swift)

    /// Each line's tokens from a serial line scan.
    private static let serial = LineLexerTests.lineScan(text, language: .swift).map(Array.init)

    @Test
    func `the visible lines come first, then the lines below them, then those above`() async {
        let emitted = Emitted()
        let source = TextLines(Self.text)

        let states = await ProgressiveHighlighting.run(
            source, lexer: Self.lexer, visibleLines: 1_500 ..< 1_560, chunkLines: 256, emit: emitted.record)

        #expect(
            emitted.order == [
                1_500 ..< 1_560, 1_560 ..< 1_816, 1_816 ..< 2_000, 0 ..< 256, 256 ..< 512, 512 ..< 768, 768 ..< 1_024,
                1_024 ..< 1_280, 1_280 ..< 1_500
            ])
        #expect(emitted.landed(lineCount: 2_000).map { $0 ?? [] } == Self.serial)
        #expect(states.exactLines == 2_000)
    }

    @Test
    func `visible lines inside a comment an earlier line opened are sent again, coloured as the comment`() async {
        let emitted = Emitted()

        _ = await ProgressiveHighlighting.run(
            TextLines(Self.text), lexer: Self.lexer, visibleLines: 1_000 ..< 1_030, emit: emitted.record)

        #expect(emitted.order.prefix(2) == [1_000 ..< 1_030, 1_000 ..< 1_030])
        let landed = emitted.landed(lineCount: 2_000)
        #expect(landed[1_000]?.map(\.role) == [.comment])
        #expect(landed[1_020]?.map(\.role) == [.comment, .keyword, .number])
        #expect(landed.map { $0 ?? [] } == Self.serial)
    }

    @Test
    func `known states lex the visible lines once, from their exact state`() async {
        let source = TextLines(Self.text)
        let states = await ProgressiveHighlighting.run(source, lexer: Self.lexer, visibleLines: 0 ..< 0) { _, _ in }
        let emitted = Emitted()

        _ = await ProgressiveHighlighting.run(
            source, lexer: Self.lexer, visibleLines: 1_000 ..< 1_030, states: states, emit: emitted.record)

        #expect(emitted.order.filter { $0 == 1_000 ..< 1_030 }.count == 1)
        #expect(emitted.landed(lineCount: 2_000)[1_000]?.map(\.role) == [.comment])
    }

    @Test
    func `a cancelled run emits nothing more and keeps the states it found`() async {
        let emitted = Emitted()

        // A child task, so cancelling the task the run is in leaves the test's own alone.
        async let run = ProgressiveHighlighting.run(
            TextLines(Self.text), lexer: Self.lexer, visibleLines: 1_900 ..< 1_950, chunkLines: 100
        ) { lines, tokens in
            emitted.record(lines, tokens)
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let states = await run

        #expect(emitted.order == [1_900 ..< 1_950])
        #expect(states.exactLines == 1)
    }

    @Test
    func `the lexical tier's updates equal the whole-text scan's, in utf16 offsets`() async throws {
        let text = LexerCorpus.text(.swift, fragments: 300)
        let lines = TextLines(text)
        let request = TierRequest(
            revision: SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob")), text: text,
            lineRanges: lines.lineRanges, visibleLines: 40 ..< 80, unit: .utf16)
        let emitted = Emitted()

        try await LexicalTier().run(request) { update in emitted.record(update.lines, update.tokens) }

        let utf8 = text.utf8Span
        let whole = request.lineTokens(
            LexicalHighlightEngine().highlight(utf8: utf8.span, language: .swift), lines: 0 ..< lines.lineCount)
        #expect(emitted.landed(lineCount: lines.lineCount).map { $0 ?? [] } == whole.map(Array.init))
    }

    @Test(arguments: [1, 3, 8])
    func `parallel pieces equal a serial scan, across a seam inside a comment`(parallelism: Int) async throws {
        // 6,000 lines: in three pieces, a comment runs across the seam at line 2,000; the last one never closes.
        var lines = (0 ..< 6_000).map { "let value\($0) = 1 // note" }
        lines[1_990] = "/* opens before the first seam"
        lines[2_010] = "closes after it */ let x = 2"
        lines[5_990] = "/* opens and never closes"
        let text = lines.joined(separator: "\n") + "\n"

        let (tokens, states) = try await ProgressiveHighlighting.lexAll(
            TextLines(text), lexer: Self.lexer, parallelism: parallelism)

        #expect(tokens == LineLexerTests.lineScan(text, language: .swift))
        #expect(states.exactLines == 6_000)
        let serial = await ProgressiveHighlighting.run(TextLines(text), lexer: Self.lexer, visibleLines: 0 ..< 0) {
            _, _ in
        }
        #expect(states == serial)
    }
}
