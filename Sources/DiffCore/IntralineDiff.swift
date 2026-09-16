/// Emphasis for a pair of changed lines, at the granularity the viewer asks for.
public enum IntralineDiff {
    /// Longest line, in UTF-16 units, for which an intraline diff is attempted.
    public static let maximumLineLength = 2000

    /// Above this share of changed units the whole line reads as replaced and no emphasis is returned.
    public static let maximumChangedShare = 0.5

    /// More ranges than this per side means the lines only share scattered pieces, which is not worth emphasizing.
    public static let maximumRangesPerSide = 4

    /// Ranges, in UTF-16 offsets, of the removed units in `old` and the inserted units in `new`.
    /// - Parameters:
    ///   - oldTokens: Token ranges of `old` for the syntax tier; words are used when absent.
    ///   - newTokens: Token ranges of `new` for the syntax tier; words are used when absent.
    /// - Returns: nil when the lines are too long or too different for the emphasis to help.
    public static func emphasis(
        old: Substring,
        new: Substring,
        granularity: IntralineGranularity = .character,
        oldTokens: [Range<Int>]? = nil,
        newTokens: [Range<Int>]? = nil,
        refiners: [any IntralineRefining] = []
    ) -> (old: [Range<Int>], new: [Range<Int>])? {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        guard oldUnits.count <= maximumLineLength, newUnits.count <= maximumLineLength else { return nil }

        // Indentation is never the change worth pointing at: compare past it and shift the ranges back.
        let oldLead = oldUnits.prefix { $0 == 32 || $0 == 9 }.count
        let newLead = newUnits.prefix { $0 == 32 || $0 == 9 }.count
        let oldRanges = ranges(of: oldUnits, granularity: granularity, tokens: oldTokens).compactMap { Self.trimmed($0, lead: oldLead) }
        let newRanges = ranges(of: newUnits, granularity: granularity, tokens: newTokens).compactMap { Self.trimmed($0, lead: newLead) }
        var edits = LineDiff.diff(oldRanges.map { oldUnits[$0] }, newRanges.map { newUnits[$0] }, anchoringRareLines: false)
        for refiner in refiners {
            edits = refiner.refine(edits, oldRanges: oldRanges, newRanges: newRanges)
        }

        var oldEmphasis: [Range<Int>] = []
        var newEmphasis: [Range<Int>] = []
        var changed = 0
        for edit in edits {
            switch edit {
            case .equal:
                continue
            case .delete(let index):
                oldEmphasis.extend(with: oldRanges[index])
                changed += oldRanges[index].count
            case .insert(let index):
                newEmphasis.extend(with: newRanges[index])
                changed += newRanges[index].count
            }
        }

        let total = max(oldUnits.count + newUnits.count, 1)
        guard Double(changed) / Double(total) <= maximumChangedShare,
              oldEmphasis.count <= maximumRangesPerSide, newEmphasis.count <= maximumRangesPerSide
        else { return nil }
        return (oldEmphasis, newEmphasis)
    }

    private static func trimmed(_ range: Range<Int>, lead: Int) -> Range<Int>? {
        range.upperBound <= lead ? nil : max(range.lowerBound, lead)..<range.upperBound
    }

    private static func ranges(of units: [UInt16], granularity: IntralineGranularity, tokens: [Range<Int>]?) -> [Range<Int>] {
        switch granularity {
        case .character: (0..<units.count).map { $0..<($0 + 1) }
        case .word: IntralineTokenizer.words(units)
        case .syntax: tokens ?? IntralineTokenizer.codeTokens(units)
        }
    }
}

private extension [Range<Int>] {
    mutating func extend(with range: Range<Int>) {
        if let last, last.upperBound == range.lowerBound {
            self[count - 1] = last.lowerBound..<range.upperBound
        } else {
            append(range)
        }
    }
}
