import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Copying from a pane writes the source's characters: where the text shows a placeholder for a bidi control, the copy
/// holds the control itself, as it did before the panes showed placeholders.
@MainActor
struct BidiControlCopyTests {
    private static let rlo = "\u{202E}"
    private static let pdf = "\u{202C}"
    private static let line = "abc\(rlo)def\(pdf)ghi"

    private func rendered(_ text: String) throws -> RenderedText {
        try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
    }

    /// What copying `ranges` of `textView` writes: what `copy(_:)` writes to the general pasteboard, written to a
    /// pasteboard of the test's own.
    private func copied(
        _ ranges: [NSRange], from textView: NSTextView, as types: [NSPasteboard.PasteboardType]? = nil
    ) throws -> String? {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        textView.selectedRanges = ranges.map { NSValue(range: $0) }
        try #require(textView.writeSelection(to: pasteboard, types: types ?? textView.writablePasteboardTypes))
        return pasteboard.string(forType: .string)
    }

    /// The text view within `view`'s subviews.
    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    /// The text view of a scrolling pane showing `rendered`, as SwiftUI makes it.
    private func scrollingPane(showing rendered: RenderedText) throws -> NSTextView {
        let host = NSHostingController(rootView: DiffTextView(rendered: rendered, gutter: .new, showsMinimap: false))
        host.view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.view.layoutSubtreeIfNeeded()
        return try #require(textView(in: host.view))
    }

    /// The text view of a card pane showing `rendered`'s diff, as SwiftUI makes it.
    private func cardPane(showing diff: RenderedDiff) throws -> NSTextView {
        let host = NSHostingController(
            rootView: EmbeddedDiffTextView(layouts: CardLayouts(rendered: diff), side: .new, gutter: .new, width: 600))
        host.sizingOptions = []
        host.view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.view.layoutSubtreeIfNeeded()
        return try #require(textView(in: host.view))
    }

    @Test
    func `copying from a scrolling pane writes the controls behind the placeholders`() throws {
        let rendered = try rendered(Self.line + "\n")
        let textView = try scrollingPane(showing: rendered)

        #expect(try copied([NSRange(location: 0, length: 11)], from: textView) == Self.line)
    }

    @Test
    func `copying from a card pane writes the controls behind the placeholders`() throws {
        let diff = DiffRenderer.render(oldText: Self.line + "\n", newText: Self.line + "\n", language: .plain)
        let textView = try cardPane(showing: diff)

        #expect(try copied([NSRange(location: 0, length: 11)], from: textView) == Self.line)
    }

    @Test
    func `copying as the modern plain text type writes the controls too`() throws {
        let textView = DiffPaneTextView(usingTextLayoutManager: true)
        try #require(textView.textStorage).setAttributedString(rendered(Self.line + "\n").attributed)

        let copy = try copied([NSRange(location: 2, length: 7)], from: textView, as: [.string])

        #expect(copy == "c\(Self.rlo)def\(Self.pdf)g")
    }

    @Test
    func `a discontiguous selection copies its ranges a newline apart, controls and all`() throws {
        let textView = DiffPaneTextView(usingTextLayoutManager: true)
        try #require(textView.textStorage).setAttributedString(rendered("\(Self.line)\nplain row\n").attributed)

        let copy = try copied([NSRange(location: 2, length: 3), NSRange(location: 12, length: 5)], from: textView)

        #expect(copy == "c\(Self.rlo)d\nplain")
    }

    @Test
    func `a selection without placeholders copies as a plain text view copies it`() throws {
        let attributed = try rendered("\(Self.line)\nplain row\n").attributed
        let pane = DiffPaneTextView(usingTextLayoutManager: true)
        try #require(pane.textStorage).setAttributedString(attributed)
        let plain = NSTextView(usingTextLayoutManager: true)
        try #require(plain.textStorage).setAttributedString(attributed)
        let selection = [NSRange(location: 12, length: 9)]

        #expect(try copied(selection, from: pane) == copied(selection, from: plain))
    }

    @Test
    func `the source of a run of placeholders holds each control, from any unit of the run on`() throws {
        // Two RLOs in a row share one attribute run.
        let attributed = try rendered("a\(Self.rlo)\(Self.rlo)\(Self.pdf)b\n").attributed

        #expect(attributed.sourceText(in: NSRange(location: 0, length: 5)) == "a\(Self.rlo)\(Self.rlo)\(Self.pdf)b")
        #expect(attributed.sourceText(in: NSRange(location: 2, length: 3)) == "\(Self.rlo)\(Self.pdf)b")
    }
}
