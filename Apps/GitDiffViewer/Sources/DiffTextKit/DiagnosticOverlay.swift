package import AtelierDiagnostics
import Darwin
package import DiffRendering
import Foundation
import Synchronization

/// Whether the calling thread is the main thread, for asserting that work runs off it.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// Per-pane row annotations, written on the main actor and read on TextKit's drawing threads under a `Mutex`.
package final class DiagnosticOverlay: Sendable {
    /// Everything a row needs to draw its diagnostics: the worst severity present, how many findings landed on
    /// it, the findings themselves (for a click to show), and where to underline within the row's text.
    package struct RowDiagnostics: Equatable, Sendable {
        /// The most severe finding on the row.
        package let severity: Finding.Severity
        package let count: Int
        package let findings: [Finding]
        /// UTF-16 column ranges within the row's own text to underline; empty underlines the whole line.
        package let squiggles: [SquiggleRange]

        package init(severity: Finding.Severity, count: Int, findings: [Finding], squiggles: [SquiggleRange]) {
            self.severity = severity
            self.count = count
            self.findings = findings
            self.squiggles = squiggles
        }

        /// The findings whose underline covers `column`, a zero-based UTF-16 column within the row's text: one with a
        /// column from it to its end column on the same line, or to the row's end; one without, the whole line. The
        /// ranges are ``DiagnosticRowMapper``'s, before it clamps them to the row.
        package func findings(underColumn column: Int) -> [Finding] {
            findings.filter { finding in
                guard let first = finding.column else { return true }
                let start = first - 1
                let end =
                    if let endColumn = finding.endColumn, finding.endLine == nil || finding.endLine == finding.line {
                        endColumn - 1
                    } else {
                        Int.max
                    }
                return start <= column && column < end
            }
        }
    }

    /// A span to underline, zero-based UTF-16 columns within the row's own text. `end` is `nil` when the finding's
    /// range runs past the row (a multi-line span, or no end column reported), which underlines to the row's end.
    package struct SquiggleRange: Equatable, Sendable {
        package let start: Int
        package let end: Int?
        package let severity: Finding.Severity

        package init(start: Int, end: Int?, severity: Finding.Severity) {
            self.start = start
            self.end = end
            self.severity = severity
        }
    }

    private let storage: Mutex<[Int: RowDiagnostics]>

    package init(rows: [Int: RowDiagnostics] = [:]) {
        storage = Mutex(rows)
    }

    /// Swaps in a whole new set of row diagnostics, atomically: readers never see a half-updated map.
    package func replace(_ rows: [Int: RowDiagnostics]) {
        storage.withLock { $0 = rows }
    }

    package func row(_ index: Int) -> RowDiagnostics? {
        storage.withLock { $0[index] }
    }

    /// Every row's diagnostics as one value, so a pane can copy them and tell which rows a later replace changed.
    package func snapshot() -> [Int: RowDiagnostics] {
        storage.withLock { $0 }
    }

    package var isEmpty: Bool {
        storage.withLock { $0.isEmpty }
    }
}

/// One side's findings, as the row mapper reads them: the path each rendered file's findings are keyed under, by file
/// index, and the side's findings by path.
package struct SideFindings: Sendable {
    package let paths: [Int: String]
    package let findings: [String: [Finding]]

    package init(paths: [Int: String], findings: [String: [Finding]]) {
        self.paths = paths
        self.findings = findings
    }

    /// A side that was not analyzed.
    package static let none = SideFindings(paths: [:], findings: [:])

    /// The findings on `line` of the file at `fileIndex`.
    func findings(atLine line: Int, fileIndex: Int) -> [Finding] {
        guard let path = paths[fileIndex], let candidates = findings[path] else { return [] }
        return candidates.filter { $0.line == line }
    }
}

/// Builds a `DiagnosticOverlay`'s rows for one rendered text. Each side's findings show on that side's rows only
/// (DIAG-08): the old pane shows the left side's by old line number, the new pane the right side's by new line
/// number, and the unified text a removed row the left side's, an added row the right side's, and an unchanged row,
/// which belongs to both, each side's once.
package enum DiagnosticRowMapper {
    /// The same mapping as ``rows(for:left:right:)``, always off the main actor.
    @concurrent
    package static func rowsOffMain(
        for rendered: RenderedText, left: SideFindings, right: SideFindings
    ) async -> [Int: DiagnosticOverlay.RowDiagnostics] {
        assert(!isOnMainThread(), "rowsOffMain must run off the main actor")
        return rows(for: rendered, left: left, right: right)
    }

    package static func rows(
        for rendered: RenderedText, left: SideFindings, right: SideFindings
    ) -> [Int: DiagnosticOverlay.RowDiagnostics] {
        var byRow: [Int: [Finding]] = [:]
        for (rowIndex, meta) in rendered.rows.enumerated() {
            var matches: [Finding] = []
            if rendered.side != .old, let newNumber = meta.newNumber {
                matches = right.findings(atLine: newNumber, fileIndex: meta.fileIndex)
            }
            if rendered.side != .new, let oldNumber = meta.oldNumber {
                // An unchanged row belongs to both sides: a finding both report on it shows once.
                let seen = Set(matches.map(RowKey.init))
                matches += left.findings(atLine: oldNumber, fileIndex: meta.fileIndex)
                    .filter {
                        !seen.contains(RowKey($0))
                    }
            }
            guard !matches.isEmpty else { continue }
            byRow[rowIndex] = matches
        }

        var result: [Int: DiagnosticOverlay.RowDiagnostics] = [:]
        for (rowIndex, rowFindings) in byRow {
            let length = rowLength(for: rowIndex, in: rendered)
            let severity = rowFindings.map(\.severity).max() ?? .note
            let squiggles = rowFindings.compactMap { finding -> DiagnosticOverlay.SquiggleRange? in
                guard let column = finding.column else { return nil }
                let start = max(0, min(column - 1, length))
                let end: Int?
                if let endColumn = finding.endColumn, finding.endLine == nil || finding.endLine == finding.line {
                    end = max(start, min(endColumn - 1, length))
                } else {
                    end = nil
                }
                return DiagnosticOverlay.SquiggleRange(start: start, end: end, severity: finding.severity)
            }
            result[rowIndex] = DiagnosticOverlay.RowDiagnostics(
                severity: severity, count: rowFindings.count, findings: rowFindings, squiggles: squiggles)
        }
        return result
    }

    /// What makes two sides' findings on one unchanged row the same finding.
    private struct RowKey: Hashable {
        let tool: DiagnosticTool
        let ruleID: String
        let message: String
        let column: Int?

        init(_ finding: Finding) {
            tool = finding.tool
            ruleID = finding.ruleID
            message = finding.message
            column = finding.column
        }
    }

    /// The row's own UTF-16 length, its trailing newline (and the `\r` of a `\r\n`) trimmed off: `RenderedText`
    /// spans every row from one line start to the next, newline included.
    private static func rowLength(for rowIndex: Int, in rendered: RenderedText) -> Int {
        let start = rendered.lineStarts[rowIndex]
        let end =
            rowIndex + 1 < rendered.lineStarts.count ? rendered.lineStarts[rowIndex + 1] : rendered.attributed.length
        var length = end - start
        guard length > 0 else { return 0 }
        let string = rendered.attributed.string as NSString
        if string.character(at: start + length - 1) == 0x0A {
            length -= 1
            if length > 0, string.character(at: start + length - 1) == 0x0D { length -= 1 }
        }
        return max(length, 0)
    }
}
