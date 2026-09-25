import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The main-thread cost of one hover's panel: every block built as a view and measured on a throwaway TextKit stack,
/// then laid out again in its own text view, the content stack laid out twice on the way. Each document is timed in
/// phases: the document built from the markdown, off the main thread in the app; the panel's render on the panel
/// every hover of a pane reuses, and on a new one, as a pane's first hover builds; the throwaway measurements alone;
/// the first display pass after a render, which lays the text views out for drawing; and each scroll that builds the
/// next blocks of a discussion longer than the panel.
///
/// Run in release, alone on the machine: `GDV_BENCH=1 swift test -c release -Xswiftc -enable-testing
/// --scratch-path .build-release --filter HoverBuildBenchmark`.
@MainActor
@Suite(.mainActorLane)
struct HoverBuildBenchmark {
    private static let runs = 21

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `a hover's panel, on the SDK's Bool and on two hundred blocks with a long code block`() throws {
        let documents = [
            ("the SDK's Bool", HoverFixtures.sdkBool, HoverContent.Source.sdk),
            ("200 blocks and a 2,000-line code block", Self.longDocument, .languageServer)
        ]
        let appearance = try #require(NSAppearance(named: .aqua))
        for (name, markdown, source) in documents {
            let content = HoverContent(markdown: markdown, source: source)
            var build: [Double] = []
            var document = HoverDocument.build(from: content, palette: .system)
            for _ in 0 ..< Self.runs {
                build.append(Self.milliseconds { document = HoverDocument.build(from: content, palette: .system) })
            }

            let reused = HoverDocPanel(ordersWindowIn: false)
            reused.prepareOffscreenForTests(document: document, appearance: appearance)
            var render: [Double] = []
            var firstRender: [Double] = []
            var measure: [Double] = []
            var display: [Double] = []
            var scrolls: [Double] = []
            for _ in 0 ..< Self.runs {
                render.append(
                    Self.milliseconds { reused.prepareOffscreenForTests(document: document, appearance: appearance) })
                let root = try #require(reused.contentViewForTests)
                let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
                display.append(Self.milliseconds { root.cacheDisplay(in: root.bounds, to: bitmap) })
                measure.append(Self.milliseconds { Self.measureEveryBlock(of: document) })
                scrolls += Self.scrollThrough(reused)
                let fresh = HoverDocPanel(ordersWindowIn: false)
                firstRender.append(
                    Self.milliseconds { fresh.prepareOffscreenForTests(document: document, appearance: appearance) })
            }
            print(
                "BENCH hover build, \(name), \(Self.blockCount(document.discussion)) blocks: "
                    + "document \(Self.summary(build)); render \(Self.summary(render)); "
                    + "render on a new panel \(Self.summary(firstRender)); "
                    + "of which throwaway measurements \(Self.summary(measure)); "
                    + "first display pass \(Self.summary(display)); "
                    + (scrolls.isEmpty
                        ? "every block built by the render"
                        : "\(scrolls.count / Self.runs) scrolls building the rest, each \(Self.summary(scrolls)), "
                            + "longest \(String(format: "%.2f", scrolls.max() ?? 0)) ms"))
        }
    }

    /// Two hundred blocks, headings, paragraphs and lists in turn, around a 2,000-line Swift code block.
    private static let longDocument: String = {
        var parts = ["```swift\nfunc load(from url: URL) throws -> Config\n```", "Loads the configuration."]
        for index in 0 ..< 100 {
            switch index % 3 {
                case 0: parts.append("## Section \(index)")
                case 1:
                    parts.append(
                        "Paragraph \(index) says what the configuration holds, with `inline code`, *emphasis* and "
                            + "a [link](https://example.com/\(index)), long enough to wrap over two lines.")
                default: parts.append("- first item of list \(index)\n- second item, with `code`")
            }
            if index == 50 {
                let lines = (0 ..< 2_000).map { "let value\($0) = compute(\($0), scale: \($0 % 7))" }
                parts.append("```swift\n" + lines.joined(separator: "\n") + "\n```")
            }
            parts.append("A closing line for block \(index).")
        }
        return parts.joined(separator: "\n\n")
    }()

    /// The time of each scroll to the end of `panel`'s body that builds more of its discussion, until it is all built.
    private static func scrollThrough(_ panel: HoverDocPanel) -> [Double] {
        let clip = panel.bodyScrollView.contentView
        var samples: [Double] = []
        while panel.pendingDiscussion != nil, samples.count < 1_000 {
            samples.append(
                milliseconds {
                    clip.scroll(to: NSPoint(x: 0, y: max(panel.bodyDocument.frame.height - clip.bounds.height, 0)))
                })
        }
        return samples
    }

    /// Measures every text the discussion's blocks show, as the panel measures each on a throwaway stack.
    private static func measureEveryBlock(of document: HoverDocument) {
        let width = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        func measure(_ blocks: [HoverDocument.Block], width: CGFloat) {
            for block in blocks {
                switch block {
                    case .paragraph(let text), .heading(_, let text):
                        _ = HoverDocPanel.measuredHeight(of: text, width: width)
                    case .code(let code):
                        _ = HoverDocPanel.measuredHeight(
                            of: code, width: width - 2 * HoverPanelMetrics.chipHorizontalPadding)
                    case .list(_, _, let items):
                        for item in items { measure(item, width: width - HoverBlockMetrics.markerWidth) }
                    case .quote(let blocks):
                        measure(blocks, width: width - HoverBlockMetrics.quoteBarWidth - HoverBlockMetrics.quoteGap)
                    case .rule: break
                }
            }
        }
        measure(document.discussion, width: width)
    }

    private static func blockCount(_ blocks: [HoverDocument.Block]) -> Int {
        blocks.reduce(0) { count, block in
            switch block {
                case .list(_, _, let items): count + 1 + items.map(blockCount).reduce(0, +)
                case .quote(let blocks): count + 1 + blockCount(blocks)
                default: count + 1
            }
        }
    }

    private static func milliseconds(_ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let elapsed = clock.measure(work)
        let components = elapsed.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.2f", value) }
        return "median \(format(sorted[sorted.count / 2])) ms (p10 \(format(sorted[sorted.count / 10])), "
            + "p90 \(format(sorted[sorted.count * 9 / 10])))"
    }
}
