/// The spans of every line of a document, where a line without spans is one not highlighted yet, which the editor
/// draws as plain text.
///
/// Only one run of lines is stored; every line outside it has no spans. A refresh that highlights the screen alone
/// so stores the screen's lines, not an empty entry for each line of the document: at a million lines that array
/// took 3.5 ms of the main actor per refresh. A full pass's result is stored whole, without a copy.
public struct LineHighlights: Sendable {
    /// The number of lines, stored or not.
    @usableFromInline var lineCount: Int
    /// The line `stored` starts at.
    @usableFromInline var offset: Int
    /// The spans of the lines `offset ..< offset + stored.count`.
    @usableFromInline var stored: [[StyledSpan]]

    /// `count` lines, none of them highlighted.
    public init(unhighlightedLineCount count: Int) {
        precondition(count >= 0, "a line count is never negative")
        self.lineCount = count
        self.offset = 0
        self.stored = []
    }

    /// The lines `lines` holds, stored as they are.
    public init(_ lines: [[StyledSpan]]) {
        self.lineCount = lines.count
        self.offset = 0
        self.stored = lines
    }

    /// The stored run, for tests that check where its storage lives and who else holds it.
    var storedLines: [[StyledSpan]] {
        get { stored }
        _modify { yield &stored }
    }

    /// The lines of the stored run, as indices of the document.
    @usableFromInline var storedRange: Range<Int> { offset ..< offset + stored.count }

    /// Widens the stored run to cover `range` with lines without spans, so a write to `range` lands in it.
    /// - Complexity: O(the lines added between the run and `range`), none when the run already covers it.
    @usableFromInline mutating func storeLines(in range: Range<Int>) {
        if stored.isEmpty {
            offset = range.lowerBound
            stored = Array(repeating: [], count: range.count)
            return
        }
        if range.upperBound > storedRange.upperBound {
            stored.append(contentsOf: repeatElement([], count: range.upperBound - storedRange.upperBound))
        }
        if range.lowerBound < offset {
            stored.insert(contentsOf: repeatElement([], count: offset - range.lowerBound), at: 0)
            offset = range.lowerBound
        }
    }
}

extension LineHighlights: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public typealias Index = Int
    public typealias Element = [StyledSpan]
    public typealias Indices = Range<Int>

    public init() {
        self.init(unhighlightedLineCount: 0)
    }

    /// The number of lines, stored or not.
    @inlinable public var count: Int { lineCount }
    @inlinable public var startIndex: Int { 0 }
    @inlinable public var endIndex: Int { count }
    @inlinable public var indices: Range<Int> { 0 ..< count }

    @inlinable public subscript(position: Int) -> [StyledSpan] {
        get {
            precondition(position >= 0 && position < count, "line index out of range")
            let local = position - offset
            return local >= 0 && local < stored.count ? stored[local] : []
        }
        set {
            precondition(position >= 0 && position < count, "line index out of range")
            storeLines(in: position ..< position + 1)
            stored[position - offset] = newValue
        }
    }

    /// Replaces the lines `subrange` with `newElements`. A replacement inside or next to the stored run edits it in
    /// place; one elsewhere first fills the gap with lines without spans, unless it only puts lines without spans in
    /// place of others.
    /// - Complexity: O(the stored lines after `subrange` + `newElements.count`), plus the gap filled.
    @inlinable public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C)
    where C.Element == [StyledSpan] {
        precondition(subrange.lowerBound >= 0 && subrange.upperBound <= count, "line range out of bounds")
        let newCount = count - subrange.count + newElements.count
        let outsideStoredRun =
            stored.isEmpty || subrange.upperBound <= offset || subrange.lowerBound >= storedRange.upperBound
        if outsideStoredRun, newElements.allSatisfy(\.isEmpty) {
            // Lines without spans in place of lines without spans stay unstored; before the run, they move it.
            if !stored.isEmpty, subrange.upperBound <= offset { offset += newElements.count - subrange.count }
            lineCount = newCount
            return
        }
        storeLines(in: subrange)
        stored.replaceSubrange(subrange.lowerBound - offset ..< subrange.upperBound - offset, with: newElements)
        lineCount = newCount
    }
}

extension LineHighlights: Equatable {
    /// Two documents' highlights are equal when their lines are, however each stores them.
    public static func == (lhs: LineHighlights, rhs: LineHighlights) -> Bool {
        lhs.count == rhs.count && lhs.elementsEqual(rhs)
    }
}

extension LineHighlights: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: [StyledSpan]...) {
        self.init(elements)
    }
}
