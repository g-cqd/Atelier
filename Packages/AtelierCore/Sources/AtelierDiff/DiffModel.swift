public import AtelierSyntaxModel

public enum RowKind: Sendable {
    case context
    case added
    case removed
    /// A changed line that has a counterpart on the other side; used by the split view only.
    case modified
    /// Empty space that keeps the two panes of the split view aligned.
    case filler
    /// Rows hidden between two hunks in the changes-only layout.
    case gap
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
        if granularity == .syntax {
            layout.oldTokens = tokenRanges.tokenRangesByLine(text: oldText, language: language)
            layout.newTokens = tokenRanges.tokenRangesByLine(text: newText, language: language)
        }
        let edits = LineDiff.diffLines(oldLines, newLines, pipeline: pipeline)
        for edit in edits {
            layout.append(edit)
        }
        layout.flushChange()
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
        var oldTokens: [[Range<Int>]] = []
        var newTokens: [[Range<Int>]] = []
        var unified: [DiffRow] = []
        var split: [DiffRow] = []
        var unifiedStarts: [Int] = []
        var splitStarts: [Int] = []
        var unifiedRanges: [Range<Int>] = []
        var splitRanges: [Range<Int>] = []
        private var pendingOld: [Int] = []
        private var pendingNew: [Int] = []

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
            for pair in pairs {
                guard let oldOffset = pair.old, let newOffset = pair.new else { continue }
                let oldIndex = pendingOld[oldOffset]
                let newIndex = pendingNew[newOffset]
                let emphasis = IntralineDiff.emphasis(
                    old: oldLines[oldIndex],
                    new: newLines[newIndex],
                    granularity: granularity,
                    oldTokens: oldIndex < oldTokens.count ? oldTokens[oldIndex] : nil,
                    newTokens: newIndex < newTokens.count ? newTokens[newIndex] : nil,
                    refiners: pipeline.intralineRefiners
                )
                guard let emphasis else { continue }
                oldRefs[oldOffset] = DiffLineRef(index: oldIndex, emphasis: emphasis.old)
                newRefs[newOffset] = DiffLineRef(index: newIndex, emphasis: emphasis.new)
            }

            for ref in oldRefs { unified.append(DiffRow(kind: .removed, old: ref, new: nil)) }
            for ref in newRefs { unified.append(DiffRow(kind: .added, old: nil, new: ref)) }

            for pair in pairs {
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
