import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
import Foundation
import QuartzCore
import Testing

@testable import DiffTextKit

/// The main-thread cost of a diagnostics bump, from the update to the end of the display pass it causes: the
/// whole-layout invalidation the pane ran before, against ``DiffTextViewCoordinator/updateDiagnostics(_:version:)``,
/// which redraws the rows it changed. Runs interleave the two; run in release with GDV_BENCH=1.
@MainActor
@Suite(.mainActorLane)
struct DiagnosticRedrawBenchmark {
    /// Which rows a bump changes.
    enum Change: CaseIterable, CustomStringConvertible {
        /// One row in view.
        case oneRow
        /// Every tenth row of the document, as when a new analysis lands.
        case everyTenthRow

        var description: String {
            switch self {
                case .oneRow: "one row in view"
                case .everyTenthRow: "every tenth row"
            }
        }

        /// The rows after bump `run` of a document of `count` rows: their severity alternates from one bump to the
        /// next, so every bump changes every one of them.
        func rows(count: Int, run: Int) -> [Int: DiagnosticOverlay.RowDiagnostics] {
            let diagnostics = DiagnosticOverlay.RowDiagnostics(
                severity: run.isMultiple(of: 2) ? .warning : .error, count: 1, findings: [], squiggles: [])
            switch self {
                case .oneRow: return [1: diagnostics]
                case .everyTenthRow:
                    let rows = stride(from: 0, to: count, by: 10)
                    return Dictionary(uniqueKeysWithValues: rows.map { ($0, diagnostics) })
            }
        }
    }

    private static let runs = 11

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil), arguments: [false, true])
    func `a diagnostics bump at five and fifty thousand rows`(wrapsLines: Bool) throws {
        for count in [5_000, 50_000] {
            let rendered = try Self.rendered(rows: count)
            for change in Change.allCases {
                let invalidating = try BenchmarkPane(rendered: rendered, wrapsLines: wrapsLines)
                let redrawing = try BenchmarkPane(rendered: rendered, wrapsLines: wrapsLines)
                // One bump each first, which the samples leave out.
                invalidating.bump(to: change.rows(count: count, run: 1), version: 1, invalidatingLayout: true)
                redrawing.bump(to: change.rows(count: count, run: 1), version: 1, invalidatingLayout: false)
                var layout: [Double] = []
                var redraw: [Double] = []
                var idle: [Double] = []
                for run in 2 ..< Self.runs + 2 {
                    let rows = change.rows(count: count, run: run)
                    if run.isMultiple(of: 2) {
                        layout.append(invalidating.bump(to: rows, version: run, invalidatingLayout: true))
                        redraw.append(redrawing.bump(to: rows, version: run, invalidatingLayout: false))
                    } else {
                        redraw.append(redrawing.bump(to: rows, version: run, invalidatingLayout: false))
                        layout.append(invalidating.bump(to: rows, version: run, invalidatingLayout: true))
                    }
                    idle.append(redrawing.idlePass())
                }
                print(
                    "BENCH diagnostics bump, \(count) rows, \(wrapsLines ? "wrapped" : "unwrapped"), \(change): "
                        + "whole-layout invalidation \(Self.summary(layout)); redraw \(Self.summary(redraw)); "
                        + "a pass with nothing to draw \(Self.summary(idle))")
            }
        }
    }

    /// A text of `rows` short lines of code, as the renderer builds it.
    private static func rendered(rows: Int) throws -> RenderedText {
        let text = (0 ..< rows).map { "    let value\($0) = compute(\($0), scale: \($0 % 7))" }.joined(separator: "\n")
        return try #require(DiffRenderer.render(oldText: text + "\n", newText: text + "\n", language: .plain).new)
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.2f", value) }
        return "median \(format(sorted[sorted.count / 2])) ms (p10 \(format(sorted[sorted.count / 10])), "
            + "p90 \(format(sorted[sorted.count * 9 / 10])))"
    }
}

/// A scrolling pane built as ``DiffTextView/makeNSView(context:)`` builds it, in a window that is never ordered in.
@MainActor
private final class BenchmarkPane {
    private let window: NSWindow
    private let coordinator = DiffTextViewCoordinator()
    private let textView: NSTextView
    private let gutterView: DiffGutterView
    /// The caller's overlay, which the pane copies at each update.
    private let overlay = DiagnosticOverlay()
    private let clock = ContinuousClock()

    init(rendered: RenderedText, wrapsLines: Bool) throws {
        let scrollView = DiffPaneTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        textView = try #require(scrollView.documentView as? NSTextView)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textLayoutManager?.delegate = coordinator.fragmentProvider
        DiffTextViewCoordinator.configureWrapping(
            wrapsLines, column: 0, font: rendered.palette.font, textView: textView, scrollView: scrollView)
        gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.source = textView
        gutterView.style = .new
        gutterView.overlay = coordinator.diagnostics
        coordinator.updateDiagnostics(overlay, version: 0)
        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        coordinator.textView = textView
        coordinator.gutterView = gutterView
        coordinator.minimapView = minimapView
        coordinator.wrapsLines = wrapsLines
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(DiffTextViewCoordinator.viewportDidResize(_:)),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator, selector: #selector(DiffTextViewCoordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification, object: textView)
        coordinator.apply(rendered)
        let pane = DiffPaneView(
            gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let contentView = try #require(window.contentView)
        contentView.wantsLayer = true
        pane.frame = contentView.bounds
        pane.autoresizingMask = [.width, .height]
        contentView.addSubview(pane)
        settle()
    }

    /// Changes the diagnostics to `rows` and lets the change reach the screen; returns the milliseconds that took.
    /// Invalidating the layout is what the pane did before: it drew the caller's overlay, and invalidated the whole
    /// layout on every change.
    @discardableResult
    func bump(to rows: [Int: DiagnosticOverlay.RowDiagnostics], version: Int, invalidatingLayout: Bool) -> Double {
        overlay.replace(rows)
        let start = clock.now
        if invalidatingLayout, let layoutManager = textView.textLayoutManager {
            coordinator.diagnostics.replace(rows)
            gutterView.overlay = coordinator.diagnostics
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
            textView.needsLayout = true
            textView.needsDisplay = true
            gutterView.needsDisplay = true
        } else {
            coordinator.updateDiagnostics(overlay, version: version)
        }
        settle()
        return milliseconds(since: start)
    }

    /// The same pass with nothing changed: the floor under both ways of bumping.
    func idlePass() -> Double {
        let start = clock.now
        settle()
        return milliseconds(since: start)
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = (clock.now - start).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    /// Lays out, displays what needs it, lets the run loop turn once, and commits what was drawn.
    private func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        CATransaction.flush()
    }
}
