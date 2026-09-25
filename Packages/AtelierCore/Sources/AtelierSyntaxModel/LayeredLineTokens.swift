/// Each tier's tokens for the lines of one text, merged a line at a time (PERF-11, P1c's per-line merge).
///
/// The coverage rule decides which layers a line shows:
/// 1. The highest ``TierCoverage/complete`` layer that has landed on the line wins, and every layer below it is
///    dropped: it speaks for every byte, a byte without a token included, which is plain text on purpose.
/// 2. Each ``TierCoverage/sparse`` layer above it is added.
/// 3. What remains is painted by layer, the higher over the lower, as ``HighlightMerger`` paints it: each tier's
///    tokens on a line are ascending and disjoint, so within a layer nothing overlaps, and the merge lays each layer
///    over the one below in one pass over their tokens.
///
/// No role means "plain", so without the rule a lexer's keyword on a name a complete tier leaves uncoloured would show
/// through. Before any complete layer lands, the lowest layer that has is the baseline.
public struct LayeredLineTokens: Sendable {
    /// One layer's tokens: the coverage its tier declared, and each line's tokens once an update covered it.
    private struct Layer: Sendable {
        var coverage: TierCoverage
        var lines: [ArraySlice<LineToken>?]
    }

    public let lineCount: Int
    private var layers: [HighlightLayer: Layer] = [:]

    public init(lineCount: Int) {
        self.lineCount = lineCount
    }

    /// Whether any layer has landed on any line.
    public var isEmpty: Bool { layers.isEmpty }

    /// The layers that have landed on `line`, lowest first.
    public func layers(onLine line: Int) -> [HighlightLayer] {
        layers.filter { $0.value.lines.indices.contains(line) && $0.value.lines[line] != nil }.keys.sorted()
    }

    /// Takes `update`'s tokens for its lines, replacing what its layer had there. Lines outside the text are ignored.
    /// - Complexity: O(lines of `update`), plus O(``lineCount``) the first time its layer lands.
    public mutating func apply(_ update: TierUpdate) {
        var layer =
            layers[update.layer] ?? Layer(coverage: update.coverage, lines: Array(repeating: nil, count: lineCount))
        layer.coverage = update.coverage
        for (offset, line) in update.lines.enumerated() where line >= 0 && line < lineCount {
            layer.lines[line] = update.tokens[offset]
        }
        layers[update.layer] = layer
    }

    /// Line `line`'s tokens under the coverage rule, ascending and disjoint, each range relative to the line's start;
    /// nil when no layer has landed on the line.
    /// - Complexity: O(tokens of the layers shown on the line), with no per-byte map.
    public func merged(line: Int) -> [LineToken]? {
        guard line >= 0, line < lineCount else { return nil }
        var landed: [(layer: HighlightLayer, coverage: TierCoverage, tokens: ArraySlice<LineToken>)] = []
        for (layer, entry) in layers {
            if let tokens = entry.lines[line] { landed.append((layer, entry.coverage, tokens)) }
        }
        guard !landed.isEmpty else { return nil }
        landed.sort { $0.layer < $1.layer }
        let base = landed.lastIndex { $0.coverage == .complete } ?? 0
        var merged = Self.overlay([], with: landed[base].tokens)
        for entry in landed[(base + 1)...] where entry.coverage == .sparse {
            merged = Self.overlay(merged, with: entry.tokens)
        }
        return merged
    }

    /// `upper` laid over `lower`: each byte takes `upper`'s token where one covers it, and `lower`'s elsewhere, cut
    /// around `upper`'s. Both are ascending; where one's own tokens overlap, the earlier keeps the bytes they share,
    /// and an empty token is dropped, so the result is ascending and disjoint whatever the input.
    /// - Complexity: O(`lower.count` + `upper.count`)
    static func overlay(_ lower: [LineToken], with upper: ArraySlice<LineToken>) -> [LineToken] {
        var result: [LineToken] = []
        result.reserveCapacity(lower.count + 2 * upper.count)
        // Every byte before `cursor` has its token.
        var cursor = 0
        var next = 0
        /// Adds the pieces of `lower`'s tokens that lie between `cursor` and `end`.
        func takeLower(upTo end: Int) {
            while next < lower.count {
                let token = lower[next]
                let range = token.range
                if range.upperBound <= cursor {
                    next += 1
                    continue
                }
                guard range.lowerBound < end else { return }
                let piece = max(range.lowerBound, cursor) ..< min(range.upperBound, end)
                if !piece.isEmpty {
                    result.append(LineToken(range: piece, role: token.role, modifiers: token.modifiers))
                    cursor = piece.upperBound
                }
                guard range.upperBound <= end else { return }
                next += 1
            }
        }
        for token in upper {
            let range = max(token.range.lowerBound, cursor) ..< token.range.upperBound
            guard !range.isEmpty else { continue }
            takeLower(upTo: range.lowerBound)
            result.append(LineToken(range: range, role: token.role, modifiers: token.modifiers))
            cursor = range.upperBound
        }
        takeLower(upTo: .max)
        return result
    }
}
