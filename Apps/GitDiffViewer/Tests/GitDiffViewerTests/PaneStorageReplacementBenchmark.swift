import AppKit
import Foundation
import QuartzCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A new document in a scrolling pane that holds a large one, as the renderer design measures it: the text in, the
/// first screen laid out, drawn and committed. The storage is replaced in place, as before, or emptied first in the
/// same transaction, as ``DiffTextViewCoordinator/apply(_:keepingScroll:)`` does now. Runs interleave the two; run in
/// release with GDV_BENCH=1.
@MainActor
struct PaneStorageReplacementBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `a new document at five and fifty thousand rows`() throws {
        for (rows, runs) in [(5_000, 11), (50_000, 5)] {
            let first = PaneStorageReplacementTests.rendered(rows: rows, token: "before")
            let second = PaneStorageReplacementTests.rendered(rows: rows, token: "after")
            let replacing = try NewDocumentPane(showing: first)
            let emptying = try NewDocumentPane(showing: first)
            var replaced: [Double] = []
            var emptied: [Double] = []
            for run in 0 ..< runs {
                let next = run.isMultiple(of: 2) ? second : first
                if run.isMultiple(of: 2) {
                    replaced.append(replacing.show(next, emptyingFirst: false))
                    emptied.append(emptying.show(next, emptyingFirst: true))
                } else {
                    emptied.append(emptying.show(next, emptyingFirst: true))
                    replaced.append(replacing.show(next, emptyingFirst: false))
                }
            }
            print(
                "BENCH new document, \(rows) rows: replaced in place \(Self.summary(replaced)); "
                    + "emptied first \(Self.summary(emptied))")
            #expect(emptied.sorted()[runs / 2] < replaced.sorted()[runs / 2])
        }
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.1f", value) }
        let median = format(sorted[sorted.count / 2])
        return "median \(median) ms (min \(format(sorted[0])), max \(format(sorted[sorted.count - 1])))"
    }
}

/// A scrolling pane that never wraps, set up by ``DiffTextViewCoordinator`` in a window that is never ordered in.
@MainActor
private final class NewDocumentPane {
    private let window: NSWindow
    private let textView: NSTextView
    private let coordinator = DiffTextViewCoordinator()
    private let clock = ContinuousClock()

    init(showing rendered: RenderedText) throws {
        let scrollView = DiffPaneTextView.scrollableTextView()
        textView = try #require(scrollView.documentView as? NSTextView)
        textView.isEditable = false
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textLayoutManager?.delegate = coordinator.fragmentProvider
        DiffTextViewCoordinator.configureWrapping(
            false, column: 0, font: rendered.palette.font, textView: textView, scrollView: scrollView)
        coordinator.textView = textView
        coordinator.wrapsLines = false
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let contentView = try #require(window.contentView)
        contentView.wantsLayer = true
        scrollView.frame = contentView.bounds
        contentView.addSubview(scrollView)
        coordinator.apply(rendered)
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    /// Shows `rendered` in place of the pane's text and returns the milliseconds until it is on screen.
    func show(_ rendered: RenderedText, emptyingFirst: Bool) -> Double {
        guard let content = textView.textContentStorage, let storage = content.textStorage else { return .nan }
        coordinator.fragmentProvider.rendered = rendered
        let start = clock.now
        content.performEditingTransaction {
            if emptyingFirst { storage.setAttributedString(NSAttributedString()) }
            storage.setAttributedString(rendered.attributed)
        }
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        textView.needsDisplay = true
        window.displayIfNeeded()
        CATransaction.flush()
        let elapsed = (clock.now - start).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }
}
