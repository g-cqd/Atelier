import AemiCore
import AemiRuntime
import AemiTesting
import AppKit
import AtelierProcess
import Foundation
import Observation
import QuartzCore
import SwiftUI
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
@testable import GitDiffViewer

/// Opening a file from the file list, and going back to the list by closing its tab (book PERF-10), in the window's
/// whole content, toolbar and explorers included, laid out and drawn in a window that is never ordered in.
///
/// Each switch counts from the call the click makes to the end of the display pass that puts the new content on
/// screen: the file for an open; the first card, then the whole list, for a close. Alongside the wall time, the main
/// thread's own CPU time over the same span tells a stall from a wait. The medians are held to the budgets below.
///
/// It runs once with the explorers above the detail area, the default, and once with them in the sidebar. The detail
/// area's height in the first depends on how the split view divides the window, so the number of cards on screen is
/// printed with each result.
///
/// Run in release, alone on the machine: `GDV_BENCH=1 GDV_BENCH_REPO=path swift test -c release -Xswiftc
/// -enable-testing --filter FileListSwitchBenchmark`. GDV_BENCH_LEFT and GDV_BENCH_RIGHT pick the refs, and
/// GDV_BENCH_RUNS the switches timed per file.
@MainActor
struct FileListSwitchBenchmark {
    /// Median milliseconds from the click on a file of the list to the end of the display pass that shows it. Measured
    /// on the Atelier repository, 200 cards: 99 to 202 ms before PERF-10 and 60 to 77 ms after with nothing else
    /// loading the machine, and up to 1.5 times as much on the same machine in a busier hour. The budget covers the
    /// busier hour and still fails a return of the sidebar placement's 185 to 202 ms.
    static let openBudget = 150.0
    /// Median milliseconds from closing the last tab to the end of the display pass that shows the whole list: 149 to
    /// 252 ms before, 70 to 77 ms after, measured alongside, with the same allowance.
    static let closeBudget = 150.0

    private let scratchDefaults = ScratchDefaults(tag: "switch-bench")

    // Serialized: the placements would otherwise share the main thread and time each other.
    @Test(
        .serialized, .timeLimit(.minutes(10)),
        .enabled(
            if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil
                && ProcessInfo.processInfo.environment["GDV_BENCH_REPO"] != nil),
        arguments: [ExplorerPlacement.top, .sidebar])
    func `opening a file from the list and closing its tab`(placement: ExplorerPlacement) async throws {
        let environment = ProcessInfo.processInfo.environment
        let repo = URL(filePath: environment["GDV_BENCH_REPO"] ?? ".", directoryHint: .isDirectory)
        let leftRef = environment["GDV_BENCH_LEFT"] ?? "HEAD~1"
        let rightRef = environment["GDV_BENCH_RIGHT"] ?? "HEAD"
        let runs = environment["GDV_BENCH_RUNS"].flatMap(Int.init) ?? 9
        let bench = try await SwitchBench(
            repo: repo, leftRef: leftRef, rightRef: rightRef, placement: placement, defaults: scratchDefaults)
        defer { bench.close() }

        for path in bench.filesToOpen() {
            var open = SwitchSamples()
            var close = SwitchSamples()
            // One switch each way first, which the samples leave out.
            for run in 0 ... runs {
                let opened = try await bench.open(path)
                let closed = try await bench.closeTab()
                guard run > 0 else { continue }
                open.append(opened)
                close.append(closed)
            }
            print(
                "BENCH \(placement.rawValue) switch \(path), \(bench.rows(of: path)) card rows, "
                    + "\(bench.cardCount) cards, \(close.cardsOnScreen.max() ?? 0) on screen: "
                    + "open \(Self.summary(open.shown)), main thread \(Self.summary(open.mainThread)); "
                    + "close to first card \(Self.summary(close.firstCard)), "
                    + "to whole list \(Self.summary(close.shown)), main thread \(Self.summary(close.mainThread)); "
                    + "footprint with the file open \(Self.megabytes(open.footprint)), with the list "
                    + "\(Self.megabytes(close.footprint))")
            #expect(Self.median(open.shown) <= Self.openBudget, "opening \(path)")
            #expect(Self.median(close.shown) <= Self.closeBudget, "closing \(path)")
        }
    }

    static func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    static func megabytes(_ samples: [Double]) -> String {
        String(format: "median %.1f MB", median(samples))
    }

    static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.1f", value) }
        let spread = "min \(format(sorted[0])), max \(format(sorted[sorted.count - 1])), n \(sorted.count)"
        return "median \(format(median(samples))) ms (\(spread))"
    }
}

/// One switch: wall milliseconds until its content was on screen, the main thread's CPU milliseconds meanwhile, and
/// the process's memory footprint once it settled.
struct SwitchTiming {
    /// Until the first card was on screen; the same as `shown` for an open.
    var firstCard: Double
    var shown: Double
    var mainThread: Double
    /// Megabytes.
    var footprint: Double
    /// Cards laid out in the window once the list showed; none for an open.
    var cardsOnScreen = 0
}

/// Samples of switches in one direction.
struct SwitchSamples {
    var firstCard: [Double] = []
    var shown: [Double] = []
    var mainThread: [Double] = []
    var footprint: [Double] = []
    var cardsOnScreen: [Int] = []

    mutating func append(_ timing: SwitchTiming) {
        cardsOnScreen.append(timing.cardsOnScreen)
        firstCard.append(timing.firstCard)
        shown.append(timing.shown)
        mainThread.append(timing.mainThread)
        footprint.append(timing.footprint)
    }
}

/// The window content of one comparison against the real loader, in a window that is never ordered in.
@MainActor
final class SwitchBench {
    let model: DiffViewerModel
    private let window: NSWindow
    private let spy: TaskProviderSpy
    private let pool: BlockingOffloadPool
    private let clock = ContinuousClock()

    init(
        repo: URL, leftRef: String, rightRef: String, placement: ExplorerPlacement, defaults: ScratchDefaults
    ) async throws {
        spy = TaskProviderSpy(label: "switch-bench", defaultTimeout: .seconds(120))
        pool = BlockingOffloadPool(width: 4)
        let loader = SourceLoader(runner: HardenedProcessRunner(pool: pool), pool: pool)
        let settings = ViewerSettings(defaults: defaults.defaults)
        settings.explorerPlacement = placement
        model = DiffViewerModel(settings: settings, reader: loader, taskProvider: spy)
        // The style of the app's comparison windows: the content runs beneath the toolbar.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(settings: settings, model: model))
        pump()

        model.compareGitChanges(in: repo, leftRef: leftRef, rightRef: rightRef)
        while model.isRendering || model.left.isLoading || model.right.isLoading || model.renderedFiles.isEmpty {
            await Self.nextChange {
                _ = model.renderedFiles
                _ = model.isRendering
                _ = model.left.isLoading
                _ = model.right.isLoading
            }
        }
        try #require(!model.renderedFiles.isEmpty, "\(leftRef) and \(rightRef) compare equal; nothing to switch")
        try await settle()
        try #require(cardsOnScreen() > 0, "the file list never reached the window")
    }

    func close() {
        window.close()
        pool.shutdown()
    }

    var cardCount: Int { model.renderedFiles.count }

    /// The first card of the list, and the card with the most rows.
    func filesToOpen() -> [String] {
        let files = model.renderedFiles
        guard let first = files.first else { return [] }
        let largest = files.max { rows(of: $0) < rows(of: $1) }
        return [first.path] + (largest.map { $0.path == first.path ? [] : [$0.path] } ?? [])
    }

    func rows(of path: String) -> Int {
        model.renderedFiles.first { $0.path == path }.map(rows(of:)) ?? 0
    }

    private func rows(of file: RenderedFile) -> Int {
        file.rendered.new?.rows.count ?? file.rendered.unified?.rows.count ?? 0
    }

    /// Opens `path` as a click in the explorer does, and times it until the display pass that draws it has ended.
    func open(_ path: String) async throws -> SwitchTiming {
        let start = clock.now
        let cpu = Self.mainThreadCPU()
        model.select(path)
        while model.rendered == nil {
            await Self.nextChange { _ = model.rendered }
        }
        pump()
        let shown = Self.milliseconds(clock.now - start)
        let mainThread = Self.mainThreadCPU() - cpu
        let rendered = try #require(model.rendered?.new ?? model.rendered?.unified)
        try #require(showsText(rendered.attributed.string), "\(path) is not on screen after its display pass")
        try await settle()
        return SwitchTiming(firstCard: shown, shown: shown, mainThread: mainThread, footprint: Self.footprint())
    }

    /// Closes the active tab, the last one, as its close button does, and times it until the display pass that draws
    /// the first card, and until the one that draws the whole list.
    func closeTab() async throws -> SwitchTiming {
        let tab = try #require(model.tabs.active)
        let count = model.combinedFiles.count
        let start = clock.now
        let cpu = Self.mainThreadCPU()
        model.closeTab(tab.id)
        while model.renderedFiles.isEmpty {
            await Self.nextChange { _ = model.renderedFiles }
        }
        pump()
        let firstCard = Self.milliseconds(clock.now - start)
        try #require(cardsOnScreen() > 0, "no card is on screen after the list's first display pass")
        while model.isRendering || model.renderedFiles.count < count {
            await Self.nextChange {
                _ = model.isRendering
                _ = model.renderedFiles
            }
        }
        pump()
        let shown = Self.milliseconds(clock.now - start)
        let mainThread = Self.mainThreadCPU() - cpu
        let cards = cardsOnScreen()
        try await settle()
        return SwitchTiming(
            firstCard: firstCard, shown: shown, mainThread: mainThread, footprint: Self.footprint(),
            cardsOnScreen: cards)
    }

    /// One turn of the run loop, then a layout and display pass of the whole window, committed.
    private func pump() {
        RunLoop.main.run(mode: .default, before: .distantPast)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    /// Lets every task the model spawned end, then draws what they left.
    private func settle() async throws {
        try await spy.waitForAllTasks()
        pump()
        try await spy.waitForAllTasks()
        pump()
    }

    private func cardsOnScreen() -> Int {
        views(of: StickyCardView.self).count
    }

    private func showsText(_ text: String) -> Bool {
        views(of: DiffPaneTextView.self).contains { $0.string == text }
    }

    private func views<View: NSView>(of type: View.Type) -> [View] {
        var found: [View] = []
        var pending: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = pending.popLast() {
            if let match = view as? View { found.append(match) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }

    /// Suspends until one of the observable properties `read` touches changes.
    private static func nextChange(_ read: @MainActor () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking(read) { continuation.resume() }
        }
    }

    /// The CPU time the calling thread, the main one here, has used, in milliseconds.
    private static func mainThreadCPU() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6
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

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
