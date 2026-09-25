import AemiTesting
import AppKit
import DiffCore
import Foundation
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
@testable import GitDiffViewer

/// A long card in the card list (book CARD-12, fix plan §9 rows 18 and 19): a scroll step with the list deep in the
/// card, and a reveal there, a gap's handle dragged three rows, with the re-render it causes. The list is the app's
/// own, in a window that is never ordered in.
///
/// A scroll step moves the list 40 points, then lays out and displays what needs it, as one wheel event does. Each
/// round jumps three quarters down the card, steps ten times down, then ten times up. A reveal counts from the drag to
/// the end of the display pass that shows the card's new render; the revealed rows are hidden again between two
/// reveals, untimed. Between the timed steps, every row the card shows is checked against a whole layout of the same
/// text (DIFF-06), and the footprint is read once the rounds end.
///
/// Run in release, alone on the machine: `GDV_BENCH=1 swift test -c release -Xswiftc -enable-testing --scratch-path
/// .build-release --filter CardScrollBenchmark`. GDV_BENCH_ROWS picks one card length (5,000 and 20,000 rows
/// otherwise), GDV_BENCH_RUNS the rounds timed (each 20 steps and one reveal), GDV_BENCH_WRAP `1` or `0` one wrap mode.
/// GDV_BENCH_PROFILE `step` or `reveal` repeats that phase alone for GDV_BENCH_PROFILE_SECONDS, for a sampling
/// profiler, after writing the process's id to the file GDV_BENCH_PROFILE_MARK names.
@MainActor
@Suite(.mainActorLane)
struct CardScrollBenchmark {
    private nonisolated static let environment = ProcessInfo.processInfo.environment

    private nonisolated static var cases: [(rows: Int, wrapsLines: Bool)] {
        let rows = environment["GDV_BENCH_ROWS"].flatMap(Int.init).map { [$0] } ?? [5_000, 20_000]
        let wraps = environment["GDV_BENCH_WRAP"].map { [$0 == "1"] } ?? [false, true]
        return rows.flatMap { count in wraps.map { (count, $0) } }
    }

    private let harness = ModelTestHarness()

    // Serialized: the cards would otherwise share the main thread and time each other.
    @Test(
        .serialized, .timeLimit(.minutes(20)), .enabled(if: environment["GDV_BENCH"] != nil),
        arguments: cases)
    func `a scroll step deep in a long card, and a reveal there`(rows: Int, wrapsLines: Bool) async throws {
        let runs = Self.environment["GDV_BENCH_RUNS"].flatMap(Int.init) ?? 12
        let stepsPerRun = 10
        let sut = harness.makeSUT()
        sut.settings.mode = .inline
        sut.settings.isolatesChanges = true
        sut.settings.contextLines = 3
        sut.settings.wrapsLines = wrapsLines
        sut.settings.wrapColumn = 0
        serveOneLongFile(rows: rows)
        try await harness.load(sut)
        let list = BenchCardList(model: sut)
        defer { list.close() }
        list.pump()
        try await harness.taskProvider.waitForAllTasks()
        list.pump()
        let shownRows = try #require(sut.renderedFiles.first?.rendered.unified).rows.count
        let loadedFootprint = Self.footprint()

        if let phase = Self.environment["GDV_BENCH_PROFILE"] {
            try await profile(phase, in: list, of: sut, steps: stepsPerRun)
            return
        }

        var steps: [Double] = []
        var stepsUp: [Double] = []
        var firstSteps: [Double] = []
        var reveals: [Double] = []
        var stepsAfterReveal: [Double] = []
        // One round first, which the samples leave out.
        for run in 0 ... runs {
            let card = try list.card()
            list.scroll(toFraction: 0.75, of: card)
            for step in 0 ..< stepsPerRun {
                let elapsed = Self.time { list.scroll(by: 40) }
                guard run > 0 else { continue }
                steps.append(elapsed)
                if step == 0 { firstSteps.append(elapsed) }
            }
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after scrolling down")
            for _ in 0 ..< stepsPerRun {
                let elapsed = Self.time { list.scroll(by: -40) }
                if run > 0 { stepsUp.append(elapsed) }
            }
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after scrolling up")
            let gap = try #require(list.visibleGap(of: card), "no gap with a band shows")
            let before = try #require(sut.renderedFiles.first).rendered.id
            let reveal = Self.time {
                harness.drag(sut, .extendsChangeBelow, of: gap, rows: 3)
                list.pump(until: { list.shows(sut.renderedFiles.first?.rendered.unified) })
            }
            try #require(sut.renderedFiles.first?.rendered.id != before, "the drag revealed nothing")
            try #require(list.shows(sut.renderedFiles.first?.rendered.unified), "the card shows the old render")
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after a reveal")
            let afterReveal = Self.time { list.scroll(by: 40) }
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after a step after a reveal")
            // Rendered off the main actor, unlike a drag.
            sut.resetRevealedLines()
            try await harness.taskProvider.waitForAllTasks()
            list.pump(until: { list.shows(sut.renderedFiles.first?.rendered.unified) })
            try #require(list.shows(sut.renderedFiles.first?.rendered.unified), "the card shows the revealed render")
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after hiding the revealed rows")
            list.scroll(toFraction: 0.3, of: card)
            Self.expectPlaced(list.misplacedRows(wrapsLines: wrapsLines), "after a jump up")
            guard run > 0 else { continue }
            reveals.append(reveal)
            stepsAfterReveal.append(afterReveal)
        }
        print(
            "BENCH card scroll \(rows) rows (\(shownRows) shown), wraps \(wrapsLines): "
                + "scroll step down \(Self.summary(steps)), up \(Self.summary(stepsUp)), "
                + "first step of a round \(Self.summary(firstSteps)); "
                + "reveal \(Self.summary(reveals)), step after a reveal \(Self.summary(stepsAfterReveal)); "
                + String(
                    format: "footprint %.1f MB, %.1f MB more than once the card showed", Self.footprint(),
                    Self.footprint() - loadedFootprint))
    }

    /// Repeats `phase`, `step` or `reveal`, alone for GDV_BENCH_PROFILE_SECONDS, for a sampling profiler.
    private func profile(_ phase: String, in list: BenchCardList, of sut: DiffViewerModel, steps stepsPerRun: Int)
        async throws
    {
        // For a sampling profiler: the phase alone, over and over.
        let seconds = Self.environment["GDV_BENCH_PROFILE_SECONDS"].flatMap(Double.init) ?? 20
        let end = ContinuousClock.now + .seconds(seconds)
        // A profiler waits for this file, since the test's output reaches it only at the end.
        if let mark = Self.environment["GDV_BENCH_PROFILE_MARK"] {
            FileManager.default.createFile(atPath: mark, contents: Data("pid \(getpid())\n".utf8))
        }
        while ContinuousClock.now < end {
            let card = try list.card()
            list.scroll(toFraction: 0.75, of: card)
            if phase == "step" {
                for _ in 0 ..< 2 * stepsPerRun { list.scroll(by: 40) }
                for _ in 0 ..< 2 * stepsPerRun { list.scroll(by: -40) }
            } else {
                let gap = try #require(list.visibleGap(of: card), "no gap with a band shows")
                harness.drag(sut, .extendsChangeBelow, of: gap, rows: 3)
                list.pump(until: { list.shows(sut.renderedFiles.first?.rendered.unified) })
                sut.resetRevealedLines()
                try await harness.taskProvider.waitForAllTasks()
                list.pump(until: { list.shows(sut.renderedFiles.first?.rendered.unified) })
            }
        }
        print("PROFILE \(phase) done")
    }

    /// One file whose isolated changes show about `rows` rows: a change every twelfth line, which with three lines of
    /// context shows eight rows of every twelve lines and hides the other five in a gap. Every seventh line is long
    /// enough to wrap in the list's width.
    private func serveOneLongFile(rows: Int) {
        let count = rows * 12 / 8
        let tail = String(repeating: "long ", count: 40)
        let old = (1 ... count).map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" }
        var new = old
        for line in stride(from: 6, to: count, by: 12) { new[line] = "let value\(line + 1) = changed" }
        harness.reader.blobContents["old"] = old.joined(separator: "\n") + "\n"
        harness.reader.blobContents["new"] = new.joined(separator: "\n") + "\n"
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("long.swift", "old")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("long.swift", "new")]
    }

    /// Expects no misplaced row, naming the first few.
    private static func expectPlaced(
        _ misplaced: [Int: CGFloat], _ when: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let first = misplaced.sorted { $0.key < $1.key }.prefix(4).map { "row \($0.key) off by \($0.value)" }
        #expect(
            misplaced.isEmpty, "\(misplaced.count) rows misplaced \(when): \(first.joined(separator: ", "))",
            sourceLocation: sourceLocation)
    }

    /// The process's physical memory footprint, in megabytes.
    private static func footprint() -> Double {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Double(usage.ri_phys_footprint) / 1_048_576 : .nan
    }

    private static func time(_ work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// The median and the 10th to 90th percentiles, in milliseconds.
    private static func summary(_ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "no samples" }
        let sorted = samples.sorted()
        let pick = { (fraction: Double) in sorted[Int((Double(sorted.count - 1) * fraction).rounded())] }
        return String(
            format: "median %.2f ms (p10 %.2f, p90 %.2f, n %d)", pick(0.5), pick(0.1), pick(0.9), sorted.count)
    }
}

/// The card list of a model, in a window that is never ordered in, as tall as a window on a laptop's screen.
@MainActor
private final class BenchCardList {
    private let window: NSWindow

    init(model: DiffViewerModel) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 800), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CombinedDiffView(model: model))
    }

    func close() {
        window.close()
    }

    /// One turn of the run loop, then a layout and a display pass of the whole list; twice, since cards measure once
    /// they have a width.
    func pump() {
        for _ in 0 ..< 2 { turn() }
    }

    /// Turns until `condition` holds, then once more for the layout and display it leads to; at most eight turns.
    func pump(until condition: () -> Bool) {
        for _ in 0 ..< 8 {
            turn()
            if condition() { break }
        }
        turn()
    }

    private func turn() {
        RunLoop.main.run(mode: .default, before: .distantPast)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func card() throws -> StickyCardView {
        try #require(Self.first(StickyCardView.self, in: window.contentView))
    }

    private func list(of card: StickyCardView) throws -> NSScrollView {
        try #require(card.enclosingScrollView)
    }

    /// Scrolls the list so that its top shows the card's text `fraction` of the way down.
    func scroll(toFraction fraction: CGFloat, of card: StickyCardView) {
        guard let list = card.enclosingScrollView, let document = list.documentView,
            let textView = Self.first(NSTextView.self, in: card)
        else { return }
        let text = textView.convert(textView.bounds, to: document)
        let y = text.minY + fraction * text.height
        list.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? y : document.bounds.height - y))
        list.reflectScrolledClipView(list.contentView)
        pump()
    }

    /// One scroll step: the list moves `points` down, then lays out and displays what needs it.
    func scroll(by points: CGFloat) {
        guard let list = try? list(of: card()), let document = list.documentView else { return }
        var origin = list.contentView.bounds.origin
        origin.y += document.isFlipped ? points : -points
        list.contentView.scroll(to: origin)
        list.reflectScrolledClipView(list.contentView)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// A gap between two changes whose band shows in the list, clear of its edges.
    func visibleGap(of card: StickyCardView) -> GapMarker? {
        guard let gutter = Self.first(DiffGutterView.self, in: card), let list = card.enclosingScrollView else {
            return nil
        }
        let visible = gutter.convert(list.contentView.bounds, from: list.contentView).insetBy(dx: 0, dy: 100)
        var found: GapMarker?
        gutter.forEachGap(in: visible) { gap, _ in
            if found == nil, gap.marker.handles.contains(.extendsChangeBelow), !gap.marker.isLeading {
                found = gap.marker
            }
        }
        return found
    }

    /// The whole layout of the text the card last showed at the width it showed it: each row's top.
    private var measured: (text: RenderedText, width: CGFloat, tops: [CGFloat])?

    /// The rows the card's text view shows whose top is not where a whole layout of the same text at the same width
    /// puts it (book DIFF-06), each with how far off it is in the view; read without laying anything out. A card
    /// showing no row answers row -1.
    func misplacedRows(wrapsLines: Bool) -> [Int: CGFloat] {
        guard let card = try? card(), let textView = Self.first(NSTextView.self, in: card),
            let rendered = Self.first(DiffGutterView.self, in: card)?.rendered,
            let layoutManager = textView.textLayoutManager, let content = layoutManager.textContentManager
        else { return [-1: .nan] }
        let tops = measuredTops(of: rendered, width: textView.textContainer?.size.width ?? 0, wrapsLines: wrapsLines)
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin.y
        let start = layoutManager.documentRange.location
        var misplaced: [Int: CGFloat] = [:]
        var shown = 0
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard fragment.state == .layoutAvailable, frame.maxY + origin > visible.minY,
                frame.minY + origin < visible.maxY
            else { return true }
            shown += 1
            let row = rendered.rowIndex(containing: content.offset(from: start, to: fragment.rangeInElement.location))
            // In the text view, where the card's rows and its gutter's numbers are: the card counts its rows from the
            // space above the first, whatever the view does with its container.
            let off = frame.minY + origin - (tops[row] + StaticTextLayout.verticalInset + rendered.bandAbove)
            if abs(off) >= 0.5 { misplaced[row] = off }
            return true
        }
        if shown == 0 { misplaced[-1] = .nan }
        return misplaced
    }

    private func measuredTops(of rendered: RenderedText, width: CGFloat, wrapsLines: Bool) -> [CGFloat] {
        if let measured, measured.text === rendered, measured.width == width { return measured.tops }
        let layout = StaticTextLayout(rendered: rendered)
        // Unwrapped, a column no row reaches lays every row out on one line, as the card measures it.
        layout.layOut(mode: wrapsLines ? .viewport : .column(100_000), viewportWidth: width)
        let layoutManager = layout.layoutManager
        let start = layoutManager.documentRange.location
        var tops = [CGFloat](repeating: .nan, count: rendered.rows.count)
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let content = layoutManager.textContentManager else { return false }
            let row = rendered.rowIndex(containing: content.offset(from: start, to: fragment.rangeInElement.location))
            if tops[row].isNaN { tops[row] = fragment.layoutFragmentFrame.minY }
            return true
        }
        measured = (rendered, width, tops)
        return tops
    }

    /// Whether the card's pane shows `rendered`.
    func shows(_ rendered: RenderedText?) -> Bool {
        guard let rendered, let card = try? card(), let gutter = Self.first(DiffGutterView.self, in: card) else {
            return false
        }
        return gutter.rendered === rendered
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView?) -> View? {
        guard let view else { return nil }
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}
