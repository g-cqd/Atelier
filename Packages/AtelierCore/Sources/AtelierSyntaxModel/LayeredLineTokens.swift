/// Each tier's tokens for the lines of one text, merged a line at a time (PERF-11, P1c's per-line merge).
///
/// The coverage rule decides which layers a line shows:
/// 1. The highest ``TierCoverage/complete`` layer that has landed on the line wins, and every layer below it is
///    dropped: it speaks for every byte, a byte without a token included, which is plain text on purpose.
/// 2. Each ``TierCoverage/sparse`` layer above it is added.
/// 3. What remains is painted as ``HighlightMerger`` paints: by layer, then width, then priority.
///
/// No role means "plain", so without the rule a lexer's keyword on a name a complete tier leaves uncoloured would show
/// through. Before any complete layer lands, the lowest layer that has is the baseline.
public struct LayeredLineTokens: Sendable {
    /// One layer's tokens: the coverage its tier declared, and each line's tokens once an update covered it.
    private struct Layer: Sendable {
        var coverage: TierCoverage
        var lines: [ArraySlice<HighlightToken>?]
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
    /// - Complexity: O(tokens on the line + its covered length)
    public func merged(line: Int) -> [HighlightToken]? {
        guard line >= 0, line < lineCount else { return nil }
        let landed = layers.compactMap { key, layer in layer.lines[line].map { (key, layer.coverage, $0) } }
            .sorted { $0.0 < $1.0 }
        guard !landed.isEmpty else { return nil }
        let base = landed.lastIndex { $0.1 == .complete } ?? 0
        let shown = landed[base...].enumerated().filter { $0.offset == 0 || $0.element.1 == .sparse }.map(\.element)
        let tokens = shown.flatMap { $0.2 }
        let length = tokens.map(\.byteRange.upperBound).max() ?? 0
        return HighlightMerger.merge(tokens, sourceByteCount: length)
    }
}
