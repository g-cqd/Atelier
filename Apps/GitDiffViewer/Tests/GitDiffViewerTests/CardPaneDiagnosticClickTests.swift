import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
import SwiftUI
import Testing

@testable import DiffTextKit
@testable import GitDiffViewer

/// A click on a card pane's decorated line number opens that row's findings, as it does in the single-file view (book
/// DUI-03).
@MainActor
@Suite(.mainActorLane)
struct CardPaneDiagnosticClickTests {
    private static let row = 2

    private static func finding(line: Int) -> Finding {
        Finding(
            tool: .swiftlint, ruleID: "line_length", message: "Line should be 120 characters or less", file: "a.swift",
            line: line, column: 5, severity: .warning)
    }

    private static func diff() -> RenderedDiff {
        let text = (1 ... 6).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        return DiffRenderer.render(oldText: text, newText: text, language: .plain)
    }

    @Test
    func `a click on a card pane's decorated line number reports that row's findings`() throws {
        let findings = [Self.finding(line: Self.row + 1)]
        let overlay = DiagnosticOverlay(
            rows: [Self.row: .init(severity: .warning, count: 1, findings: findings, squiggles: [])])
        var clicks: [(row: Int, findings: [Finding])] = []
        let pane = try ClickableCardPane(diff: Self.diff(), overlay: overlay) { row, findings in
            clicks.append((row, findings))
        }

        try pane.clickLineNumber(ofRow: Self.row)

        #expect(clicks.map(\.row) == [Self.row])
        #expect(clicks.first?.findings == findings)
        // What the popover opened from the click shows.
        let content = DiagnosticFindingsPopover.content(for: try #require(clicks.first).findings)
        #expect(content.rootView.findings == findings)
    }

    @Test
    func `a click on an undecorated line number of a card pane reports nothing`() throws {
        let overlay = DiagnosticOverlay(
            rows: [Self.row: .init(severity: .warning, count: 1, findings: [Self.finding(line: 3)], squiggles: [])])
        var clicks = 0
        let pane = try ClickableCardPane(diff: Self.diff(), overlay: overlay) { _, _ in clicks += 1 }

        try pane.clickLineNumber(ofRow: 0)

        #expect(clicks == 0)
    }
}

/// A card pane with diagnostics, hosted in a borderless window that is never ordered in.
@MainActor
private final class ClickableCardPane {
    private static let width: CGFloat = 500
    private let window: NSWindow
    private let host: NSView

    init(diff: RenderedDiff, overlay: DiagnosticOverlay, onClick: @escaping (Int, [Finding]) -> Void) throws {
        let pane = EmbeddedDiffTextView(
            layouts: CardLayouts(rendered: diff), side: .new, gutter: .new, width: Self.width, wrapMode: .none,
            diagnosticOverlay: overlay, diagnosticsVersion: 0,
            onDiagnosticClick: { row, findings, _, _ in onClick(row, findings) })
        let host = NSHostingView(rootView: pane)
        self.host = host
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: max(host.fittingSize.height, 1)),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// Presses and releases the mouse over `row`'s line number, as AppKit hands the gutter the press.
    func clickLineNumber(ofRow row: Int) throws {
        let gutter = try #require(Self.first(DiffGutterView.self, in: host))
        var center: NSPoint?
        gutter.forEachFragment(in: gutter.bounds) { fragment, _, index, y in
            guard index == row else { return }
            center = NSPoint(x: gutter.bounds.midX, y: y + fragment.layoutFragmentFrame.height / 2)
        }
        let point = gutter.convert(try #require(center), to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        gutter.mouseDown(with: event)
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}
