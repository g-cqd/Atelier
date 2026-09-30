import AppKit
import DiffCore
import Metal
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Folding from the gutter and the keys (DIFF-03): the hovered capsule's `⌄` folds its scope, a folded scope's `›`
/// tab or its `•••` unfolds it, and ⌥⌘←, ⌥⌘→, ⌥⌘⇧← and ⌥⌘⇧→ act on the insertion point's scope in the focused pane.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct ScopeFoldGutterTests {
    /// The new side's `f`, lines 1 to 3 of ``ScopeLinesTests/text``.
    private static let f = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 1)

    /// The requests a gutter made.
    private final class Requests {
        var all: [ScopeFoldRequest] = []
    }

    /// A pane over ``ScopeLinesTests/text`` with its scopes landed, and `folds` folded, with its gutter's requests.
    private static func pane(folds: [ScopeFoldKey: Int] = [:]) throws
        -> (pane: HostedDecoratedPane, gutter: DiffGutterView, requests: Requests)
    {
        let text = ScopeLinesTests.text
        let prepared = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: text, newText: text, language: .swift), granularity: .word)
        let rendered = try #require(
            DiffRenderer.render(
                prepared: [prepared], options: DiffRenderer.Options(sides: [.new], foldedScopes: folds), layout: .full,
                withHeaders: false
            )
            .new)
        let decorations = DiffDecorations(new: .init(scopes: try ScopeLinesTests.scopes()), markVersion: 1)
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: decorations)
        let content = try #require(pane.window.contentView)
        let gutter = try #require(firstSubview(DiffGutterView.self, in: content))
        let requests = Requests()
        gutter.onScopeFold = { requests.all.append($0) }
        return (pane, gutter, requests)
    }

    /// Clicks `gutter` in its ribbon on `row`, or at `x` when given.
    private static func click(_ gutter: DiffGutterView, row: Int, x: CGFloat? = nil) throws {
        let frame = try #require(gutter.lineNumberFrames(in: gutter.bounds)[row])
        let point = gutter.convert(NSPoint(x: x ?? gutter.ribbonX + 2, y: frame.midY), to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: gutter.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1,
                pressure: 1))
        gutter.mouseDown(with: event)
    }

    /// Presses ←, or → when `right`, with ⌥⌘ and, when `all`, ⇧, in `textView`.
    private static func press(right: Bool, all: Bool = false, in textView: NSTextView) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: all ? [.command, .option, .shift] : [.command, .option],
                timestamp: 0, windowNumber: textView.window?.windowNumber ?? 0, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: right ? 124 : 123))
        textView.keyDown(with: event)
    }

    @Test
    func `the capsule's first end folds its scope, and a fold's tab or its capsule in the text unfolds it`() throws {
        let open = try Self.pane()
        open.gutter.hoverScope(atRow: 2)
        try Self.click(open.gutter, row: 1)
        // The number column takes no fold.
        try Self.click(open.gutter, row: 3, x: 2)

        #expect(open.requests.all == [.fold([Self.f: 3])])

        let folded = try Self.pane(folds: [Self.f: 3])
        let rendered = try #require(folded.gutter.rendered)
        let fold = try #require(rendered.folds.first)
        try Self.click(folded.gutter, row: fold.firstRow)
        let textView = try folded.pane.textView
        let tracker = ScopeHoverTracker()
        tracker.attach(to: textView, gutter: folded.gutter)
        defer { tracker.detach() }
        let screen = textView.firstRect(
            forCharacterRange: NSRange(location: fold.marker.lowerBound + 1, length: 1), actualRange: nil)
        let window = try #require(textView.window).convertFromScreen(screen)
        #expect(tracker.unfoldMarker(at: textView.convert(NSPoint(x: window.midX, y: window.midY), from: nil)))

        #expect(folded.requests.all == [.unfold([Self.f]), .unfold([Self.f])])
    }

    @Test
    func `the folding keys act on the insertion point's scope, and on every function or fold`() throws {
        let open = try Self.pane()
        let textView = try open.pane.textView
        let rendered = try #require(open.gutter.rendered)
        textView.setSelectedRange(NSRange(location: rendered.lineStarts[2] + 2, length: 0))

        try Self.press(right: false, in: textView)
        try Self.press(right: false, all: true, in: textView)
        // Nothing is folded: the key goes on as usual.
        try Self.press(right: true, in: textView)

        #expect(open.requests.all == [.fold([Self.f: 3]), .fold([Self.f: 3])])

        let folded = try Self.pane(folds: [Self.f: 3])
        let foldedView = try folded.pane.textView
        let first = try #require(folded.gutter.rendered?.folds.first?.firstRow)
        foldedView.setSelectedRange(
            NSRange(location: try #require(folded.gutter.rendered).lineStarts[first], length: 0))

        try Self.press(right: true, in: foldedView)
        try Self.press(right: true, all: true, in: foldedView)

        #expect(folded.requests.all == [.unfold([Self.f]), .unfold([Self.f])])
    }
}
