import AppKit
import DiffCore
import Foundation
import QuartzCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// One alignment pass of two wrapped side-by-side panes, as ``SplitPaneController`` runs it: both panes measured whole,
/// the spacing worked out, and written into each storage, then the next layout and display. The spacing is written
/// row by row into the live storage, as ``RowSpacing/apply(_:to:rendered:)`` does, or into a copy set into the emptied
/// storage in one transaction, as the renderer design proposes (text-renderer.md §5, M0 item 7). Every third row
/// wraps on the old side only. Runs interleave the two; run in release with GDV_BENCH=1.
@MainActor
@Suite(.mainActorLane)
struct SplitAlignmentBenchmark {
    enum Write: CustomStringConvertible {
        case perRow, rebuilt

        var description: String {
            switch self {
                case .perRow: "row by row"
                case .rebuilt: "rebuilt copy"
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `an alignment pass at five and fifty thousand rows`() throws {
        for (rows, runs) in [(5_000, 7), (50_000, 3)] {
            let diff = Self.rendered(rows: rows)
            let old = try #require(diff.old)
            let new = try #require(diff.new)
            var samples: [String: (write: [Double], pass: [Double])] = [:]
            for write in [Write.perRow, .rebuilt] {
                let left = BackendPane(kind: .textKit2, showing: old)
                let right = BackendPane(kind: .textKit2, showing: new)
                defer {
                    left.close()
                    right.close()
                }
                for run in 0 ..< runs + 1 {
                    // Every run changes the spacing: aligned, then back to none.
                    let aligns = run.isMultiple(of: 2)
                    let start = ContinuousClock.now
                    let heights = (left.pane.rowHeights().heights, right.pane.rowHeights().heights)
                    let spacing =
                        aligns ? RowAlignment.spacing(left: heights.0, right: heights.1) : (left: [], right: [])
                    let writeStart = ContinuousClock.now
                    Self.write(spacing.left, to: left, rendered: old, as: write)
                    Self.write(spacing.right, to: right, rendered: new, as: write)
                    let written = TextBackendBenchmark.milliseconds(since: writeStart)
                    left.settle()
                    right.settle()
                    let pass = TextBackendBenchmark.milliseconds(since: start)
                    // The first run warms up.
                    guard run > 0 else { continue }
                    samples[write.description, default: ([], [])].write.append(written)
                    samples[write.description, default: ([], [])].pass.append(pass)
                }
            }
            for write in [Write.perRow, .rebuilt] {
                let sample = samples[write.description] ?? ([], [])
                print(
                    "BENCH split alignment, \(rows) rows, \(write): writes \(TextBackendBenchmark.summary(sample.write)); "
                        + "whole pass \(TextBackendBenchmark.summary(sample.pass))")
            }
        }
    }

    private static func write(_ spacing: [Double], to pane: BackendPane, rendered: RenderedText, as write: Write) {
        switch write {
            case .perRow: pane.pane.setRowSpacing(spacing)
            case .rebuilt:
                guard let textView = (pane.pane as? TextKit2Pane)?.textView else { return }
                rebuild(spacing, in: textView, rendered: rendered)
        }
    }

    /// Writes `spacing` into a copy of `textView`'s text, then sets the copy into the emptied storage in one
    /// transaction.
    private static func rebuild(_ spacing: [Double], in textView: NSTextView, rendered: RenderedText) {
        guard let contentStorage = textView.textContentStorage, let storage = contentStorage.textStorage else { return }
        let copy = NSMutableAttributedString(attributedString: storage)
        let length = copy.length
        copy.beginEditing()
        for (row, start) in rendered.lineStarts.enumerated() {
            let end = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] : length
            guard end > start,
                let current = copy.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle
            else { continue }
            let target = (row < spacing.count ? spacing[row] : 0) + rendered.bandSpacing(afterRow: row)
            guard current.paragraphSpacing != target, let style = current.mutableCopy() as? NSMutableParagraphStyle
            else { continue }
            style.paragraphSpacing = target
            copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: end - start))
        }
        copy.endEditing()
        contentStorage.performEditingTransaction {
            storage.setAttributedString(NSAttributedString())
            storage.setAttributedString(copy)
        }
    }

    /// `rows` rows of code; every third one grows past the width of a 1000-point pane on the old side.
    private static func rendered(rows: Int) -> RenderedDiff {
        let new = (0 ..< rows).map { "    let value\($0) = compute(\($0), scale: \($0 % 7))" }
        let old = new.enumerated()
            .map { index, line in
                index.isMultiple(of: 3) ? line + String(repeating: " + adjustment(\(index))", count: 8) : line
            }
        return DiffRenderer.render(
            oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
            language: .plain)
    }
}
