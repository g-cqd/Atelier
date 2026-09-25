public import AtelierSyntaxModel
public import AtelierText

/// Lexing a text visible lines first (review §7.4, P1a), as tier 0 of the tier job (PERF-11).
///
/// Both entry points are caller-driven, as the core requires: `run` is an async function that emits as it goes, and
/// `lexAll`'s parallel pieces are children of a task group, so cancelling the caller's task stops them.
public enum ProgressiveHighlighting {
    /// How many lines one emitted chunk holds, past the visible ones.
    public static let defaultChunkLines = 512
    /// How often, in lines, a scan looks for its task's cancellation.
    static let cancellationInterval = 256
    /// The fewest lines `lexAll` gives one parallel piece: below that, a task costs more than it saves.
    static let minimumPieceLines = 1_024

    /// Lexes `source`'s visible lines, emits them, then the lines below them and those above, in chunks.
    ///
    /// The visible lines start from their exact state when `states` knows it. Otherwise they are lexed as if they began
    /// the text and emitted at once, then checked once the lines above them are lexed from the top; when the guess was
    /// wrong, as when they begin inside a block comment, they are lexed again and emitted a second time, so the
    /// consumer replaces what it had. Every other line is emitted once, from its exact state.
    ///
    /// Checks for cancellation before each chunk and every 256 lines. A cancelled run stops without emitting the chunk
    /// it was in and returns the states found so far, which stay valid for this text. It never throws.
    /// - Parameters:
    ///   - source: The text's lines.
    ///   - lexer: Scans a line from its entry state.
    ///   - visibleLines: The lines on screen, clamped to the text.
    ///   - states: States found for this same text before, if any; ignored when their line count differs.
    ///   - chunkLines: How many lines a chunk past the visible ones holds.
    ///   - emit: Takes each chunk: its lines and their tokens, in UTF-8 byte offsets from each line's start.
    /// - Returns: The states found, exact from the top down to the last line lexed from an exact state.
    /// - Complexity: O(bytes + tokens), plus the visible lines' once more when the guess was wrong.
    public static func run(
        _ source: some LineSource, lexer: some LineLexer, visibleLines: Range<Int>, states: LexStates? = nil,
        chunkLines: Int = defaultChunkLines, emit: (_ lines: Range<Int>, _ tokens: LineTokens) async -> Void
    ) async -> LexStates {
        let lineCount = source.lineCount
        var states = states.flatMap { $0.lineCount == lineCount ? $0 : nil } ?? LexStates(lineCount: lineCount)
        let visible = visibleLines.clamped(to: 0 ..< lineCount)
        let size = max(chunkLines, 1)

        // The visible lines, from their exact state or from a guess.
        var guess: Lexed?
        if !visible.isEmpty {
            let known = states.state(at: visible.lowerBound)
            guard !Task.isCancelled,
                let lexed = lex(source, lines: visible, from: known ?? .initial, lexer: lexer)
            else { return states }
            if known != nil { states.record(lexed, at: visible) } else { guess = lexed }
            await emit(visible, lexed.tokens)
        }

        // The lines above, lexed from the top to learn the visible lines' state, and emitted last.
        var above: [(lines: Range<Int>, tokens: LineTokens)] = []
        for lines in chunks(of: 0 ..< visible.lowerBound, size: size) {
            let entry = states.state(at: lines.lowerBound) ?? .initial
            guard !Task.isCancelled, let lexed = lex(source, lines: lines, from: entry, lexer: lexer) else {
                return states
            }
            states.record(lexed, at: lines)
            above.append((lines, lexed.tokens))
        }

        if let guess {
            let exact = states.state(at: visible.lowerBound) ?? .initial
            if exact == guess.entries[0] {
                states.record(guess, at: visible)
            } else {
                guard !Task.isCancelled, let lexed = lex(source, lines: visible, from: exact, lexer: lexer) else {
                    return states
                }
                states.record(lexed, at: visible)
                await emit(visible, lexed.tokens)
            }
        }

        for lines in chunks(of: visible.upperBound ..< lineCount, size: size) {
            let entry = states.state(at: lines.lowerBound) ?? .initial
            guard !Task.isCancelled, let lexed = lex(source, lines: lines, from: entry, lexer: lexer) else {
                return states
            }
            states.record(lexed, at: lines)
            await emit(lines, lexed.tokens)
        }
        for chunk in above {
            guard !Task.isCancelled else { return states }
            await emit(chunk.lines, chunk.tokens)
        }
        return states
    }

    /// ``run(_:lexer:visibleLines:states:chunkLines:emit:)`` over a tier request's lines, each chunk emitted as a
    /// ``TierUpdate`` of the lexical layer, complete, stamped with the request's revision, in its unit.
    public static func run(
        _ request: TierRequest, lexer: some LineLexer, states: LexStates? = nil,
        chunkLines: Int = defaultChunkLines, emit: (TierUpdate) async -> Void
    ) async -> LexStates {
        await run(
            RequestLines(text: request.text, ranges: request.lineRanges), lexer: lexer,
            visibleLines: request.visibleLines, states: states, chunkLines: chunkLines
        ) { lines, tokens in
            await emit(
                TierUpdate(
                    layer: .lexical, coverage: .complete, revision: request.revision, lines: lines,
                    tokens: request.inUnit(tokens, lines: lines)))
        }
    }

    /// Lexes every line of `source` in up to `parallelism` pieces at once, each a child of one task group.
    ///
    /// Every piece but the first starts from a guess, ``LexState/initial``. The seams are then checked in order: a
    /// piece whose guess was wrong is lexed again from the exact state, until one of its lines starts in the state the
    /// guess gave it, from which the guess's tokens stand. The result equals a serial scan's.
    /// - Parameters:
    ///   - source: The text's lines.
    ///   - lexer: Scans a line from its entry state.
    ///   - parallelism: How many pieces may be lexed at once; a piece holds at least 1,024 lines.
    /// - Returns: Every line's tokens, in UTF-8 byte offsets from each line's start, and every line's exact state.
    /// - Throws: `CancellationError` when the calling task is cancelled.
    /// - Complexity: O(bytes + tokens), spread over the pieces, plus the lines re-lexed past a wrong guess.
    public static func lexAll(
        _ source: some LineSource, lexer: some LineLexer, parallelism: Int
    ) async throws(CancellationError) -> (tokens: LineTokens, states: LexStates) {
        let lineCount = source.lineCount
        let pieces = max(1, min(parallelism, lineCount / minimumPieceLines))
        let bounds = (0 ... pieces).map { lineCount * $0 / pieces }
        var guesses = [Lexed?](repeating: nil, count: pieces)
        await withTaskGroup(of: (Int, Lexed?).self) { group in
            for piece in 0 ..< pieces {
                let lines = bounds[piece] ..< bounds[piece + 1]
                group.addTask { (piece, lex(source, lines: lines, from: .initial, lexer: lexer)) }
            }
            for await (piece, lexed) in group { guesses[piece] = lexed }
        }
        var tokens = LineTokens(emptyLines: 0)
        var states = LexStates(lineCount: lineCount)
        var entry = LexState.initial
        for piece in 0 ..< pieces {
            guard !Task.isCancelled, let guess = guesses[piece] else { throw CancellationError() }
            let lines = bounds[piece] ..< bounds[piece + 1]
            let lexed = try repair(guess, of: source, lines: lines, from: entry, lexer: lexer)
            states.record(lexed, at: lines)
            tokens.append(contentsOf: lexed.tokens)
            entry = lexed.end
        }
        return (tokens, states)
    }

    /// `guess`, the tokens of `lines` lexed from a guessed state, made exact for `entry`: lines are lexed again from
    /// `entry` until one starts in the state `guess` gave it, and `guess` stands from there.
    private static func repair(
        _ guess: Lexed, of source: some LineSource, lines: Range<Int>, from entry: LexState, lexer: some LineLexer
    ) throws(CancellationError) -> Lexed {
        guard !lines.isEmpty, guess.entries[0] != entry else { return guess }
        var state = entry
        var tokens: [LineToken] = []
        var offsets: [UInt32] = [0]
        var entries: [LexState] = []
        for line in lines {
            let offset = line - lines.lowerBound
            if offset > 0, guess.entries[offset] == state {
                var repaired = LineTokens(tokens: tokens, offsets: offsets)
                repaired.append(contentsOf: guess.tokens.lines(offset ..< lines.count))
                return Lexed(tokens: repaired, entries: entries + guess.entries[offset...], end: guess.end)
            }
            if offset % cancellationInterval == cancellationInterval - 1, Task.isCancelled {
                throw CancellationError()
            }
            entries.append(state)
            state = source.withLineBytes(at: line) { lexer.scan($0, from: state, into: &tokens) }
            offsets.append(UInt32(tokens.count))
        }
        return Lexed(tokens: LineTokens(tokens: tokens, offsets: offsets), entries: entries, end: state)
    }

    /// Lexes `lines` from `entry`; nil when the task is cancelled on the way.
    /// - Complexity: O(bytes and tokens of `lines`)
    private static func lex(
        _ source: some LineSource, lines: Range<Int>, from entry: LexState, lexer: some LineLexer
    ) -> Lexed? {
        var tokens: [LineToken] = []
        var offsets: [UInt32] = [0]
        var entries: [LexState] = []
        offsets.reserveCapacity(lines.count + 1)
        entries.reserveCapacity(lines.count)
        var state = entry
        for line in lines {
            let offset = line - lines.lowerBound
            if offset % cancellationInterval == cancellationInterval - 1, Task.isCancelled { return nil }
            entries.append(state)
            state = source.withLineBytes(at: line) { lexer.scan($0, from: state, into: &tokens) }
            offsets.append(UInt32(tokens.count))
        }
        return Lexed(tokens: LineTokens(tokens: tokens, offsets: offsets), entries: entries, end: state)
    }

    /// `range` cut into runs of at most `size` lines, in order.
    private static func chunks(of range: Range<Int>, size: Int) -> [Range<Int>] {
        stride(from: range.lowerBound, to: range.upperBound, by: size).map { $0 ..< min($0 + size, range.upperBound) }
    }
}

/// Some lines lexed from one state: their tokens, the state each started in, and the state after the last.
struct Lexed: Sendable {
    var tokens: LineTokens
    var entries: [LexState]
    var end: LexState
}

extension LexStates {
    /// Records `lexed`'s states for `lines`, and the state the line after them starts in.
    mutating func record(_ lexed: Lexed, at lines: Range<Int>) {
        for (offset, entry) in lexed.entries.enumerated() { record(entry, at: lines.lowerBound + offset) }
        record(lexed.end, at: lines.upperBound)
    }
}

/// A tier request's lines, lent from its text.
private struct RequestLines: LineSource {
    let text: String
    let ranges: [Range<Int>]

    var lineCount: Int { ranges.count }

    func withLineBytes<R, E: Error>(at index: Int, _ body: (Span<UInt8>) throws(E) -> R) throws(E) -> R {
        let utf8 = text.utf8Span
        return try body(utf8.span.extracting(ranges[index]))
    }
}
