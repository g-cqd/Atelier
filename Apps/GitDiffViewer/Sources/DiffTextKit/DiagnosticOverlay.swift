package import AtelierDiagnostics
package import DiffRendering
import Foundation
import Synchronization

/// Per-pane row annotations: written on the main actor when results land, read on TextKit's own drawing thread.
/// A `Mutex` makes that cross-thread hand-off safe without pulling drawing onto the main actor.
package final class DiagnosticOverlay: Sendable {
    /// Everything a row needs to draw its diagnostics: the worst severity present, how many findings landed on
    /// it, the findings themselves (for a click to show), and where to underline within the row's text.
    package struct RowDiagnostics: Sendable {
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
    }

    /// A span to underline, zero-based UTF-16 columns within the row's own text. `end` is `nil` when the finding's
    /// range runs past the row (a multi-line span, or no end column reported), which underlines to the row's end.
    package struct SquiggleRange: Sendable {
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

    package var isEmpty: Bool {
        storage.withLock { $0.isEmpty }
    }
}

/// Builds a `DiagnosticOverlay`'s row content for one rendered text: findings keyed by comparison-relative path,
/// with the path each rendered row's `fileIndex` belongs to. A finding annotates the row whose file matches and
/// whose new-side line number equals the finding's line (new-side only, v1).
package enum DiagnosticRowMapper {
    package static func rows(
        for rendered: RenderedText, paths: [Int: String], findings: [String: [Finding]]
    ) -> [Int: DiagnosticOverlay.RowDiagnostics] {
        var byRow: [Int: [Finding]] = [:]
        for (rowIndex, meta) in rendered.rows.enumerated() {
            guard let line = meta.newNumber, let path = paths[meta.fileIndex], let candidates = findings[path]
            else { continue }
            let matches = candidates.filter { $0.line == line }
            guard !matches.isEmpty else { continue }
            byRow[rowIndex, default: []].append(contentsOf: matches)
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
