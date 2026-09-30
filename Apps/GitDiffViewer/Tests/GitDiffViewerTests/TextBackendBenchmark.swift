import AppKit
import DiffCore
import Foundation
import QuartzCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The design's end-to-end cases for each backend (text-renderer.md §4.4, §5 M0 exit criteria), in a 1000 × 800 pt
/// window that is never ordered in, lines wrapped at the pane's width: a new document, a smooth-scroll frame, a page
/// step, a jump, a gutter tile, and the first text of a new pane. Each step lays out, displays and commits. Today the
/// one backend is TextKit 2; run in release with GDV_BENCH=1.
@MainActor
@Suite(.mainActorLane)
struct TextBackendBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `the end-to-end cases at five and fifty thousand rows`() throws {
        for kind in TextBackendKind.allCases {
            for rows in [5_000, 50_000] {
                let first = try Self.rendered(rows: rows, token: "first")
                let second = try Self.rendered(rows: rows, token: "second")
                var fresh: [Double] = []
                for run in 0 ..< 5 {
                    let start = ContinuousClock.now
                    let pane = BackendPane(kind: kind, showing: run.isMultiple(of: 2) ? first : second)
                    fresh.append(Self.milliseconds(since: start))
                    pane.close()
                }
                let pane = BackendPane(kind: kind, showing: first)
                defer { pane.close() }
                let newDocument = (0 ..< 11).map { pane.show($0.isMultiple(of: 2) ? second : first) }
                pane.show(first)
                let smooth = (0 ..< 120).map { _ in pane.scroll(by: 3 * first.lineHeight) }
                let page = (0 ..< 20).map { _ in pane.scroll(by: pane.pageHeight) }
                let jump = (0 ..< 10).map { pane.jump(toRow: rows * ($0.isMultiple(of: 2) ? 3 : 1) / 4) }
                let gutter = (0 ..< 20).map { _ in pane.drawGutter() }
                print(
                    "BENCH \(kind.title), \(rows) rows: first text in a new pane \(Self.summary(fresh)); "
                        + "new document \(Self.summary(newDocument)); smooth-scroll frame \(Self.summary(smooth)); "
                        + "page step \(Self.summary(page)); jump \(Self.summary(jump)); gutter tile "
                        + "\(Self.summary(gutter)); laid-out rows \(pane.laidOutRows()) for "
                        + "\(pane.visibleRowCount) visible")
            }
        }
    }

    /// A text of `rows` lines of code some 30 to 70 characters long, one in 17 added and one in 23 removed.
    static func rendered(rows: Int, token: String) throws -> RenderedText {
        let old = (0 ..< rows)
            .map { row in
                let tail = String(repeating: " + x", count: row % 9)
                return "    let \(token)\(row) = compute(\(row), scale: \(row % 7))" + tail
            }
        var new = old
        for index in stride(from: 0, to: rows, by: 17) { new[index] += " // added" }
        for index in stride(from: 11, to: rows, by: 23) { new[index] = "" }
        let text = DiffRenderer.render(
            oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
            language: .plain)
        return try #require(text.new)
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = (ContinuousClock.now - start).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.2f", value) }
        return "median \(format(sorted[sorted.count / 2])) ms (p10 \(format(sorted[sorted.count / 10])), "
            + "p90 \(format(sorted[sorted.count * 9 / 10])))"
    }
}

/// A pane a backend makes, in a window that is never ordered in.
@MainActor
final class BackendPane {
    private let window: NSWindow
    let pane: any DiffTextPane

    init(kind: TextBackendKind, showing rendered: RenderedText, wrapping: WrapMode = .viewport) {
        pane = DiffTextBackends.backend(for: kind).makePane(gutter: .new)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        contentView.wantsLayer = true
        window.contentView = contentView
        pane.view.frame = contentView.bounds
        pane.view.autoresizingMask = [.width, .height]
        contentView.addSubview(pane.view)
        pane.setWrapping(wrapping)
        pane.show(rendered, keepingScroll: false)
        settle()
    }

    var pageHeight: CGFloat { pane.clipView?.bounds.height ?? 0 }
    var visibleRowCount: Int { pane.geometry.visibleRows().count }

    /// Shows `rendered` in place of the text on show; returns the milliseconds until it is on screen.
    @discardableResult
    func show(_ rendered: RenderedText) -> Double {
        let start = ContinuousClock.now
        pane.show(rendered, keepingScroll: false)
        settle()
        return TextBackendBenchmark.milliseconds(since: start)
    }

    /// Scrolls `distance` down, back to the top past the end; returns the milliseconds until the frame is on screen.
    func scroll(by distance: CGFloat) -> Double {
        guard let clip = pane.clipView, let scrollView = clip.enclosingScrollView else { return 0 }
        let end = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
        let y = clip.bounds.minY + distance > end ? 0 : clip.bounds.minY + distance
        let start = ContinuousClock.now
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
        settle()
        return TextBackendBenchmark.milliseconds(since: start)
    }

    /// Brings `row` near the top, as a row asked for is; returns the milliseconds until it is on screen.
    func jump(toRow row: Int) -> Double {
        let start = ContinuousClock.now
        pane.scroll(toRow: row, centered: false)
        settle()
        return TextBackendBenchmark.milliseconds(since: start)
    }

    /// Draws the gutter over what shows; returns the milliseconds that took.
    func drawGutter() -> Double {
        guard let gutter = (pane as? TextKit2Pane)?.gutterView else { return 0 }
        let start = ContinuousClock.now
        gutter.setNeedsDisplay(gutter.visibleRect)
        gutter.displayIfNeeded()
        return TextBackendBenchmark.milliseconds(since: start)
    }

    /// How many rows the pane holds laid out.
    func laidOutRows() -> Int {
        guard let layoutManager = (pane as? TextKit2Pane)?.textView.textLayoutManager else { return 0 }
        var count = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            if fragment.state == .layoutAvailable { count += 1 }
            return true
        }
        return count
    }

    func close() {
        window.contentView = nil
    }

    /// Lays out, displays what needs it, lets the run loop turn once, and commits what was drawn.
    func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        CATransaction.flush()
    }
}
