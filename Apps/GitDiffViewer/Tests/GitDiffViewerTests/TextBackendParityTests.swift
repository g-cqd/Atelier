import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The seam's parity harness (text-renderer.md §4.4): a pane a backend makes shows each fixture as the app's own pane
/// does, at each width. Today the one backend is TextKit 2, checked against the ``DiffTextView`` the app hosts; the
/// CoreText backend joins it in M1. The fixtures run in four suites, each within the main thread's budget.
@MainActor
@Suite(.mainActorLane)
struct TextBackendParityTests {
    @Test(arguments: [TextBackendParity.Fixture.ascii, .tabs, .longLines], TextBackendParity.widths)
    func `code lays out, hit-tests, scrolls and copies as in the app's pane`(
        fixture: TextBackendParity.Fixture, width: CGFloat?
    ) throws {
        try TextBackendParity.check(fixture, width: width)
    }
}

@MainActor
@Suite(.mainActorLane)
struct TextBackendScriptParityTests {
    @Test(arguments: [TextBackendParity.Fixture.cjk, .emoji, .rightToLeft], TextBackendParity.widths)
    func `other scripts lay out, hit-test, scroll and copy as in the app's pane`(
        fixture: TextBackendParity.Fixture, width: CGFloat?
    ) throws {
        try TextBackendParity.check(fixture, width: width)
    }
}

@MainActor
@Suite(.mainActorLane)
struct TextBackendMarkParityTests {
    @Test(arguments: [TextBackendParity.Fixture.combiningMarks, .bidiControls], TextBackendParity.widths)
    func `combining marks and bidi controls lay out, hit-test, scroll and copy as in the app's pane`(
        fixture: TextBackendParity.Fixture, width: CGFloat?
    ) throws {
        try TextBackendParity.check(fixture, width: width)
    }
}

@MainActor
@Suite(.mainActorLane)
struct TextBackendGapParityTests {
    @Test(arguments: TextBackendParity.widths)
    func `gaps, headers and fillers lay out, hit-test, scroll and copy as in the app's pane`(width: CGFloat?) throws {
        try TextBackendParity.check(.gapsAndFillers, width: width)
    }
}

/// What the parity suites share: the fixtures, the widths, and the check of one against the app's pane.
@MainActor
enum TextBackendParity {
    /// The texts the backends must agree on, each a diff so its sides carry changed, filler and header rows.
    enum Fixture: String, CaseIterable, Sendable {
        case ascii, tabs, longLines, cjk, emoji, rightToLeft, combiningMarks, bidiControls, gapsAndFillers

        var lines: [String] {
            switch self {
                case .ascii: (1 ... 24).map { "let value\($0) = compute(\($0), scale: \($0 % 7))" }
                case .tabs: (1 ... 24).map { "\tif value\($0) {\n\t\treturn \($0)\t// done\n\t}" }
                case .longLines:
                    (1 ... 12).map { "let line\($0) = \"" + String(repeating: "word\($0) ", count: 30) + "\"" }
                case .cjk: (1 ... 16).map { "let 名前\($0) = \"漢字とかなの混じった文\($0)\"" }
                case .emoji: (1 ... 16).map { "let face\($0) = \"👩‍👩‍👧‍👦 🏳️‍🌈 👍🏽 \($0)\"" }
                case .rightToLeft: (1 ... 16).map { "let greeting\($0) = \"שלום עולם \($0) مرحبا\"" }
                case .combiningMarks: (1 ... 16).map { "let word\($0) = \"e\u{301}te\u{301} n\u{303}o \($0)\"" }
                case .bidiControls:
                    (1 ... 16).map { "let access\($0) = \"user\u{202E} \u{2066}// admin\u{2069} \u{2066}\($0)\"" }
                case .gapsAndFillers: (1 ... 80).map { "let value\($0) = \($0)" }
            }
        }

        /// The side a pane shows: the old side carries filler rows across from added lines, the unified one headers
        /// and the bands of gaps.
        func rendered() throws -> RenderedText {
            let old = lines.joined(separator: "\n") + "\n"
            let new =
                lines.enumerated()
                .compactMap { index, line in
                    switch index % 9 {
                        case 3: nil
                        case 5: line + " // changed"
                        case 7: line + "\n" + line.uppercased()
                        default: line
                    }
                }
                .joined(separator: "\n") + "\n"
            let layout: RenderLayout = self == .gapsAndFillers ? .changes(context: 2, expansions: [:]) : .full
            let diff = DiffRenderer.render(oldText: old, newText: new, language: .plain, layout: layout)
            return try #require(self == .gapsAndFillers ? diff.unified : diff.old)
        }
    }

    /// No wrapping, and wrapping at a pane 400 or 800 points wide.
    nonisolated static let widths: [CGFloat?] = [nil, 400, 800]

    /// Checks a TextKit 2 backend pane showing `fixture` against the app's pane, unwrapped or wrapped `width` wide.
    static func check(_ fixture: Fixture, width: CGFloat?) throws {
        let rendered = try fixture.rendered()
        let size = NSSize(width: width ?? 600, height: 240)
        let reference = try ReferencePane(rendered: rendered, wrapsLines: width != nil, size: size)
        let pane = TextKit2Backend().makePane(gutter: .dual)
        let window = Self.window(size: size, content: pane.view)
        defer { window.contentView = nil }
        pane.setWrapping(width == nil ? .none : .viewport)
        pane.show(rendered, keepingScroll: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let textView = try #require(Self.first(NSTextView.self, in: pane.view))
        Self.layOutEverything(textView)
        Self.layOutEverything(reference.textView)

        // Row frames: every row once, top to bottom, where the app's pane has it, wrapped onto as many lines.
        let rows = Self.rows(of: pane.geometry, height: textView.frame.height)
        let expected = Self.rows(of: reference.textView, rendered: rendered)
        #expect(rows.map(\.row) == Array(rendered.rows.indices))
        #expect(rows.map(\.row) == expected.map(\.row))
        for (row, reference) in zip(rows, expected) {
            #expect(abs(row.frame.minY - reference.frame.minY) <= 0.5, "row \(row.row) top")
            #expect(abs(row.frame.height - reference.frame.height) <= 0.5, "row \(row.row) height")
        }
        let lines = Self.rows(of: textView, rendered: rendered).map(\.lines)
        #expect(lines == expected.map(\.lines))
        if width == nil { #expect(lines.allSatisfy { $0 == 1 }) }
        #expect(pane.geometry.documentHeight >= (rows.last?.frame.maxY ?? 0))

        // Hover: the same identifier, row and column under each point of a grid over what shows, 10 × 10 rather than
        // the design's 20 × 20 while both panes hit-test through the same code, for the main thread's budget.
        let visible = textView.visibleRect
        for step in 0 ..< 100 {
            let point = NSPoint(
                x: visible.minX + visible.width * (CGFloat(step % 10) + 0.5) / 10,
                y: visible.minY + visible.height * (CGFloat(step / 10) + 0.5) / 10)
            let hit = pane.hoverHit(at: point)
            let expected = HoverHitTester.hit(at: point, textView: reference.textView, rendered: rendered)
            #expect(hit?.row == expected?.row && hit?.utf16Column == expected?.utf16Column, "hover at \(point)")
            if let hit { #expect(pane.anchorRect(for: hit) != nil) }
        }

        // Scrolling: the same rows show at the same offsets, and a row asked for lands where the app's pane puts it.
        let clip = try #require(pane.clipView)
        for step in 0 ..< 10 {
            let y = max(textView.frame.height - clip.bounds.height, 0) * CGFloat(step) / 9
            clip.scroll(to: NSPoint(x: 0, y: y))
            reference.clip.scroll(to: NSPoint(x: 0, y: y))
            #expect(pane.geometry.visibleRows() == reference.visibleRows(), "visible rows at \(y)")
        }
        let target = rendered.rows.count * 2 / 3
        pane.scroll(toRow: target, centered: true)
        reference.scroll(toRow: target)
        window.contentView?.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
        #expect(abs(clip.bounds.minY - reference.clip.bounds.minY) <= 1, "row \(target) placed")

        // Copy: the same text for the same selections, the bidi controls written back.
        let string = textView.string as NSString
        for step in 0 ..< 10 {
            let start = string.length * step / 10
            let range = NSRange(location: start, length: min(string.length - start, 17 + step * 23))
            #expect(Self.copy(range, from: textView) == Self.copy(range, from: reference.textView), "copy \(range)")
        }
    }

    // MARK: Helpers

    /// A laid-out row: its index, its frame in the text view, and how many lines it wraps onto.
    typealias Row = (row: Int, frame: CGRect, lines: Int)

    /// The rows a geometry reports over the whole document; it does not tell lines.
    private static func rows(of geometry: any DiffRowGeometry, height: CGFloat) -> [Row] {
        var rows: [Row] = []
        geometry.forEachRow(in: CGRect(x: 0, y: 0, width: 1, height: height)) { row, frame, _ in
            rows.append((row, frame, 0))
        }
        return rows
    }

    /// The rows a TextKit 2 text view lays out, read from its fragments.
    private static func rows(of textView: NSTextView, rendered: RenderedText) -> [Row] {
        guard let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager
        else { return [] }
        let origin = textView.textContainerOrigin
        var rows: [Row] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            let offset = contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            rows.append(
                (
                    rendered.rowIndex(containing: offset),
                    fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y),
                    fragment.textLineFragments.count
                ))
            return true
        }
        return rows
    }

    private static func layOutEverything(_ textView: NSTextView) {
        guard let layoutManager = textView.textLayoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
    }

    private static func copy(_ range: NSRange, from textView: NSTextView) -> String? {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        textView.setSelectedRange(range)
        guard textView.writeSelection(to: pasteboard, type: .string) else { return nil }
        return pasteboard.string(forType: .string)
    }

    static func window(size: NSSize, content: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        return window
    }

    static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

/// The pane the app shows today: a ``DiffTextView`` hosted in a window that is never ordered in.
@MainActor
private struct ReferencePane {
    let window: NSWindow
    let textView: NSTextView
    let clip: NSClipView
    let minimap: MinimapView

    init(rendered: RenderedText, wrapsLines: Bool, size: NSSize) throws {
        let host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .dual, wrapsLines: wrapsLines))
        window = TextBackendParity.window(size: size, content: host)
        textView = try #require(TextBackendParity.first(NSTextView.self, in: host))
        clip = try #require(textView.enclosingScrollView?.contentView)
        minimap = try #require(TextBackendParity.first(MinimapView.self, in: host))
    }

    func visibleRows() -> Range<Int> {
        minimap.visibleRows()
    }

    /// Places `row` centred, as a click on the minimap does.
    func scroll(toRow row: Int) {
        minimap.onSelectRow(row)
        window.contentView?.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
    }
}
