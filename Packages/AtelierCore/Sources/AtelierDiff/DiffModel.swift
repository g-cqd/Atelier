public import AtelierSyntaxModel

/// A syntax token provider that can return ranges for only the lines paired by a diff.
public protocol SelectedSyntaxTokenRanging: SyntaxTokenRanging {
    /// - Parameters:
    ///   - text: The whole side, lines separated by `\n`.
    ///   - language: The language the text is written in.
    ///   - lineIndices: Indices of paired lines whose UTF-16 token ranges are needed; invalid indices are ignored.
    /// - Returns: Ranges relative to each valid requested line, keyed by its zero-based index.
    /// - Complexity: O(text + returned ranges), excluding parsing.
    func tokenRangesByLine(text: String, language: Language, lineIndices: [Int]) -> [Int: [Range<Int>]]
}

public enum RowKind: Sendable {
    case context
    case added
    case removed
    /// A changed line that has a counterpart on the other side; used by the split view only.
    case modified
    /// Empty space that keeps the two panes of the split view aligned.
    case filler
    /// A file name introducing that file's hunks when several files are shown together.
    case header
}

/// A line of one side of the diff with the units to emphasize inside it.
public struct DiffLineRef: Sendable, Equatable {
    public let index: Int
    public let emphasis: [Range<Int>]

    public init(index: Int, emphasis: [Range<Int>] = []) {
        self.index = index
        self.emphasis = emphasis
    }
}

/// One row of a rendered diff. In the unified layout a row shows either side or both (context);
/// in the split layout the old side is drawn on the left and the new side on the right.
public struct DiffRow: Sendable, Equatable {
    public let kind: RowKind
    public let old: DiffLineRef?
    public let new: DiffLineRef?
    /// The line only moved: it was removed here and added unchanged elsewhere, or the reverse.
    public var isMoved = false

    public init(kind: RowKind, old: DiffLineRef?, new: DiffLineRef?, isMoved: Bool = false) {
        self.kind = kind
        self.old = old
        self.new = new
        self.isMoved = isMoved
    }
}

/// A diff between two texts, laid out both as a unified sequence and as aligned split rows.
public struct DiffModel: Sendable {
    public let oldText: String
    public let newText: String
    public let oldLines: [Substring]
    public let newLines: [Substring]
    public let unifiedRows: [DiffRow]
    public let splitRows: [DiffRow]
    /// Indices of the first row of each change, per layout.
    public let unifiedChangeStarts: [Int]
    public let splitChangeStarts: [Int]
    /// Row ranges of each change, per layout.
    public let unifiedChangeRanges: [Range<Int>]
    public let splitChangeRanges: [Range<Int>]

    /// - Parameters:
    ///   - oldText: The left side, split into lines on `\n`.
    ///   - newText: The right side, split into lines on `\n`.
    ///   - granularity: Unit of change for the emphasis inside paired lines.
    ///   - language: Drives the syntax tier's tokenizer; ignored by the other tiers.
    ///   - pipeline: The stages the diff goes through; the default wires every heuristic in.
    ///   - tokenRanges: Token boundaries for the syntax tier; ``CodeTokenRanges`` when no parser is wanted.
    public init(
        oldText: String,
        newText: String,
        granularity: IntralineGranularity = .character,
        language: Language = .plain,
        pipeline: DiffPipeline = DiffPipeline(),
        tokenRanges: any SyntaxTokenRanging
    ) {
        self.oldText = oldText
        self.newText = newText
        let oldLines = Self.lines(of: oldText)
        let newLines = Self.lines(of: newText)
        self.oldLines = oldLines
        self.newLines = newLines

        var layout = Layout(oldLines: oldLines, newLines: newLines, granularity: granularity, pipeline: pipeline)
        let edits = LineDiff.diffLines(oldLines, newLines, pipeline: pipeline)
        for edit in edits {
            layout.append(edit)
        }
        layout.flushChange()
        if granularity == .syntax {
            layout.applySyntaxEmphasis(oldText: oldText, newText: newText, language: language, tokenRanges: tokenRanges)
        }
        if pipeline.detectsMovedBlocks {
            layout.markMovedBlocks(edits)
        }

        unifiedRows = layout.unified
        splitRows = layout.split
        unifiedChangeStarts = layout.unifiedStarts
        splitChangeStarts = layout.splitStarts
        unifiedChangeRanges = layout.unifiedRanges
        splitChangeRanges = layout.splitRanges
    }

    private struct Layout {
        let oldLines: [Substring]
        let newLines: [Substring]
        let granularity: IntralineGranularity
        let pipeline: DiffPipeline
        var unified: [DiffRow] = []
        var split: [DiffRow] = []
        var unifiedStarts: [Int] = []
        var splitStarts: [Int] = []
        var unifiedRanges: [Range<Int>] = []
        var splitRanges: [Range<Int>] = []
        private var pendingOld: [Int] = []
        private var pendingNew: [Int] = []
        private var syntaxPairs: [SyntaxPair] = []

        private struct SyntaxPair {
            let oldIndex: Int
            let newIndex: Int
            let oldUnifiedRow: Int
            let newUnifiedRow: Int
            let splitRow: Int
        }

        init(oldLines: [Substring], newLines: [Substring], granularity: IntralineGranularity, pipeline: DiffPipeline) {
            self.oldLines = oldLines
            self.newLines = newLines
            self.granularity = granularity
            self.pipeline = pipeline
            unified.reserveCapacity(max(oldLines.count, newLines.count))
            split.reserveCapacity(max(oldLines.count, newLines.count))
        }

        mutating func append(_ edit: DiffEdit) {
            switch edit {
                case .equal(let old, let new):
                    flushChange()
                    let row = DiffRow(kind: .context, old: DiffLineRef(index: old), new: DiffLineRef(index: new))
                    unified.append(row)
                    split.append(row)
                case .delete(let old):
                    pendingOld.append(old)
                case .insert(let new):
                    pendingNew.append(new)
            }
        }

        mutating func flushChange() {
            guard !pendingOld.isEmpty || !pendingNew.isEmpty else { return }
            unifiedStarts.append(unified.count)
            splitStarts.append(split.count)

            let pairs = pipeline.pairing.pairs(
                removed: pendingOld.map { oldLines[$0] }, added: pendingNew.map { newLines[$0] })
            var oldRefs = pendingOld.map { DiffLineRef(index: $0) }
            var newRefs = pendingNew.map { DiffLineRef(index: $0) }
            if granularity != .syntax {
                for pair in pairs {
                    guard let oldOffset = pair.old, let newOffset = pair.new else { continue }
                    let oldIndex = pendingOld[oldOffset]
                    let newIndex = pendingNew[newOffset]
                    let emphasis = IntralineDiff.emphasis(
                        old: oldLines[oldIndex], new: newLines[newIndex], granularity: granularity,
                        refiners: pipeline.intralineRefiners)
                    guard let emphasis else { continue }
                    oldRefs[oldOffset] = DiffLineRef(index: oldIndex, emphasis: emphasis.old)
                    newRefs[newOffset] = DiffLineRef(index: newIndex, emphasis: emphasis.new)
                }
            }

            let unifiedStart = unified.count
            for ref in oldRefs { unified.append(DiffRow(kind: .removed, old: ref, new: nil)) }
            for ref in newRefs { unified.append(DiffRow(kind: .added, old: nil, new: ref)) }

            for pair in pairs {
                if granularity == .syntax, let oldOffset = pair.old, let newOffset = pair.new {
                    let oldIndex = pendingOld[oldOffset]
                    let newIndex = pendingNew[newOffset]
                    if oldLines[oldIndex].utf16.count <= IntralineDiff.maximumLineLength,
                        newLines[newIndex].utf16.count <= IntralineDiff.maximumLineLength
                    {
                        syntaxPairs.append(
                            SyntaxPair(
                                oldIndex: oldIndex, newIndex: newIndex,
                                oldUnifiedRow: unifiedStart + oldOffset,
                                newUnifiedRow: unifiedStart + oldRefs.count + newOffset,
                                splitRow: split.count))
                    }
                }
                let old = pair.old.map { oldRefs[$0] }
                let new = pair.new.map { newRefs[$0] }
                let kind: RowKind =
                    switch (old, new) {
                        case (.some, .some): .modified
                        case (.some, .none): .removed
                        default: .added
                    }
                split.append(DiffRow(kind: kind, old: old, new: new))
            }
            unifiedRanges.append(unifiedStarts[unifiedStarts.count - 1] ..< unified.count)
            splitRanges.append(splitStarts[splitStarts.count - 1] ..< split.count)
            pendingOld.removeAll(keepingCapacity: true)
            pendingNew.removeAll(keepingCapacity: true)
        }

        mutating func applySyntaxEmphasis(
            oldText: String, newText: String, language: Language, tokenRanges: any SyntaxTokenRanging
        ) {
            guard !syntaxPairs.isEmpty else { return }
            let oldTokens = selectedTokens(
                text: oldText, indices: syntaxPairs.map(\.oldIndex), language: language, provider: tokenRanges)
            let newTokens = selectedTokens(
                text: newText, indices: syntaxPairs.map(\.newIndex), language: language, provider: tokenRanges)
            for pair in syntaxPairs {
                guard
                    let emphasis = IntralineDiff.emphasis(
                        old: oldLines[pair.oldIndex], new: newLines[pair.newIndex], granularity: .syntax,
                        oldTokens: oldTokens[pair.oldIndex], newTokens: newTokens[pair.newIndex],
                        refiners: pipeline.intralineRefiners)
                else { continue }
                let oldRef = DiffLineRef(index: pair.oldIndex, emphasis: emphasis.old)
                let newRef = DiffLineRef(index: pair.newIndex, emphasis: emphasis.new)
                unified[pair.oldUnifiedRow] = DiffRow(kind: .removed, old: oldRef, new: nil)
                unified[pair.newUnifiedRow] = DiffRow(kind: .added, old: nil, new: newRef)
                split[pair.splitRow] = DiffRow(kind: .modified, old: oldRef, new: newRef)
            }
        }

        private func selectedTokens(
            text: String, indices: [Int], language: Language, provider: any SyntaxTokenRanging
        ) -> [Int: [Range<Int>]] {
            if let provider = provider as? any SelectedSyntaxTokenRanging {
                return provider.tokenRangesByLine(text: text, language: language, lineIndices: indices)
            }
            let byLine = provider.tokenRangesByLine(text: text, language: language)
            var selected: [Int: [Range<Int>]] = [:]
            selected.reserveCapacity(indices.count)
            for index in indices where index < byLine.count {
                selected[index] = byLine[index]
            }
            return selected
        }

        /// Flags rows whose lines only moved, comparing lines by their normalized text.
        mutating func markMovedBlocks(_ edits: [DiffEdit]) {
            var identifiers: [Substring: Int] = [:]
            func id(_ line: Substring) -> Int {
                let key = pipeline.whitespace.normalized(line)
                if let known = identifiers[key] { return known }
                identifiers[key] = identifiers.count
                return identifiers.count - 1
            }
            var removed: [(index: Int, id: Int)] = []
            var added: [(index: Int, id: Int)] = []
            for edit in edits {
                switch edit {
                    case .delete(let index): removed.append((index, id(oldLines[index])))
                    case .insert(let index): added.append((index, id(newLines[index])))
                    case .equal: break
                }
            }
            let moved = MovedBlocks.detect(removed: removed, added: added)
            guard !moved.old.isEmpty else { return }
            for index in unified.indices {
                let row = unified[index]
                if let old = row.old, row.kind == .removed, moved.old.contains(old.index) {
                    unified[index].isMoved = true
                }
                if let new = row.new, row.kind == .added, moved.new.contains(new.index) {
                    unified[index].isMoved = true
                }
            }
            for index in split.indices {
                let row = split[index]
                let oldMoved = row.old.map { moved.old.contains($0.index) } ?? false
                let newMoved = row.new.map { moved.new.contains($0.index) } ?? false
                if row.kind != .context, oldMoved || newMoved, row.kind != .modified || (oldMoved && newMoved) {
                    split[index].isMoved = true
                }
            }
        }
    }

    /// Splits on "\n" bytes, since Swift folds "\r\n" into one Character, drops a trailing "\r" per line so CRLF files
    /// align, and ignores the empty tail after a final newline.
    public static func lines(of text: String) -> [Substring] {
        var lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { line in
                line.last == UInt8(ascii: "\r") ? Substring(line.dropLast()) : Substring(line)
            }
        if lines.count > 1, lines[lines.count - 1].isEmpty {
            lines.removeLast()
        }
        if lines.count == 1, lines[0].isEmpty {
            return []
        }
        return lines
    }
}
