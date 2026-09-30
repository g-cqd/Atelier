package import DiffCore
import Foundation

/// One side's scopes as the gutter's ribbon draws them (DIFF-03): each scope that spans more than one line, by source
/// line, with how deeply every line nests and which scope holds it innermost. Built off the main actor once per side,
/// so the gutter reads it in constant time per row as it draws.
package struct ScopeLines: Sendable, Equatable {
    /// A scope over source lines, with where its braces lie.
    package struct Scope: Sendable, Equatable {
        /// The lines of its opening and closing braces, from zero.
        package let lines: ClosedRange<Int>
        /// Its opening brace's UTF-16 offset from its first line's start, and its closing brace's from its last line's.
        package let openColumn: Int
        package let closeColumn: Int
        package let kind: SyntaxScope.Kind
        /// How many scopes hold it, itself included: 1 for an outermost one.
        package let depth: Int

        package init(lines: ClosedRange<Int>, openColumn: Int, closeColumn: Int, kind: SyntaxScope.Kind, depth: Int) {
            self.lines = lines
            self.openColumn = openColumn
            self.closeColumn = closeColumn
            self.kind = kind
            self.depth = depth
        }
    }

    /// The scopes by their first line, an enclosing scope before those it holds.
    package let scopes: [Scope]
    /// Each line's depth: how many scopes hold it.
    private let depths: [UInt8]
    /// Each line's innermost scope, as an index into ``scopes``; -1 for a line outside every scope.
    private let innermost: [Int32]
    /// Whether a scope ends on each line.
    private let ends: [Bool]

    /// The scopes of a text of `lineRanges`, from `scopes` in UTF-8 offsets of `text`; a scope whose braces share a
    /// line is left out, since the ribbon has nothing to show for it.
    /// - Complexity: O(lines + scopes × the depth they nest to)
    package init(_ scopes: [SyntaxScope], text: String, lineRanges: [Range<Int>]) {
        let starts = lineRanges.map(\.lowerBound)
        /// The line holding the UTF-8 offset `offset`.
        func line(of offset: Int) -> Int {
            var low = 0
            var high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if starts[middle] <= offset { low = middle + 1 } else { high = middle }
            }
            return max(low - 1, 0)
        }
        let utf8 = text.utf8
        /// The UTF-16 length of `text` from `start` to `end`, UTF-8 offsets on scalar boundaries.
        func column(from start: Int, to end: Int) -> Int {
            let from = utf8.index(utf8.startIndex, offsetBy: start)
            return text.utf16.distance(from: from, to: utf8.index(from, offsetBy: end - start))
        }
        var kept: [Scope] = []
        var open: [ClosedRange<Int>] = []
        for scope in scopes where !starts.isEmpty && scope.range.upperBound <= utf8.count {
            let first = line(of: scope.range.lowerBound)
            let last = line(of: scope.range.upperBound - 1)
            guard last > first else { continue }
            while let enclosing = open.last, !(enclosing.contains(first) && enclosing.contains(last)) {
                open.removeLast()
            }
            open.append(first ... last)
            kept.append(
                Scope(
                    lines: first ... last, openColumn: column(from: starts[first], to: scope.range.lowerBound),
                    closeColumn: column(from: starts[last], to: scope.range.upperBound - 1), kind: scope.kind,
                    depth: open.count))
        }
        var depths = [UInt8](repeating: 0, count: lineRanges.count)
        var innermost = [Int32](repeating: -1, count: lineRanges.count)
        var ends = [Bool](repeating: false, count: lineRanges.count)
        for (index, scope) in kept.enumerated() {
            ends[scope.lines.upperBound] = true
            for line in scope.lines {
                if depths[line] < .max { depths[line] += 1 }
                if innermost[line] < 0 || kept[Int(innermost[line])].depth <= scope.depth {
                    innermost[line] = Int32(index)
                }
            }
        }
        self.scopes = kept
        self.depths = depths
        self.innermost = innermost
        self.ends = ends
    }

    /// How many scopes hold `line`; zero outside every scope or the text.
    package func depth(ofLine line: Int) -> Int {
        depths.indices.contains(line) ? Int(depths[line]) : 0
    }

    /// The index in ``scopes`` of the innermost scope holding `line`; nil outside every scope.
    package func innermostScope(atLine line: Int) -> Int? {
        guard innermost.indices.contains(line), innermost[line] >= 0 else { return nil }
        return Int(innermost[line])
    }

    /// Whether a scope ends on `line`.
    package func endsScope(atLine line: Int) -> Bool {
        ends.indices.contains(line) && ends[line]
    }
}

extension RenderedText {
    /// The row showing source line `line`, from zero, of the old side or the new: the first row numbered so on that
    /// side; nil when no row is.
    /// - Complexity: O(log rows), plus the unnumbered rows a probe steps over.
    package func rowIndex(ofLine line: Int, old: Bool) -> Int? {
        func number(_ row: Int) -> Int? { old ? rows[row].oldNumber : rows[row].newNumber }
        var low = 0
        var high = rows.count
        let wanted = line + 1
        while low < high {
            let middle = (low + high) / 2
            var probe = middle
            while probe < high, number(probe) == nil { probe += 1 }
            guard probe < high, let found = number(probe) else {
                high = middle
                continue
            }
            if found < wanted { low = probe + 1 } else { high = middle }
        }
        var row = low
        while row < rows.count, number(row) == nil { row += 1 }
        return row < rows.count && number(row) == wanted ? row : nil
    }
}
