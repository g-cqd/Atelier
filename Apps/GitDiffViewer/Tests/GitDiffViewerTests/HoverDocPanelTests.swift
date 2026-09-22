import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Regression coverage for the panel's own vertical rhythm: every slot in ``HoverDocPanel`` used to size itself
/// from a hand-tallied estimate (a fixed per-row guess for the parameters grid, a candidates group double-counted
/// as two of the content stack's own top-level slots, ...) that could -- and did -- drift from what Auto Layout
/// actually drew, leaving real, visible empty space at the bottom of the panel past where its content stopped.
/// ``HoverDocPanel/show(document:anchorRect:in:)`` now sizes the window from the very same `NSStackView` fitting
/// size it lays the content out with, so the two can never disagree; these tests check that invariant directly
/// against three fixtures of increasing shape, the same span the user's own screenshots covered.
@MainActor
struct HoverDocPanelTests {
    @MainActor
    private final class WindowRetainer {
        private var windows: [NSWindow] = []
        func append(_ window: NSWindow) { windows.append(window) }
    }

    private let retainedWindows = WindowRetainer()

    /// A borderless, real (but off-screen) host window with a text view inside, the same shape
    /// `DocHoverControllerTests` hosts its own fixtures in -- `HoverDocPanel` needs a real `NSWindow` to attach
    /// its child panel to and to read an `NSScreen` off of.
    private func makeHostTextView() -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(textView)
        retainedWindows.append(window)
        return textView
    }

    private func codeAttributed(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
    }

    private func prose(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }

    /// Asserts ``HoverDocPanel/panelHeightForTests`` (what the window was actually sized to) matches
    /// ``HoverDocPanel/laidOutContentHeightForTests`` (what the laid-out content stack really needs) for
    /// `document`, within a point of floating-point slop.
    private func assertNoWastedSpace(
        _ document: HoverDocument, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let panel = HoverDocPanel()
        let textView = makeHostTextView()
        panel.show(document: document, anchorRect: NSRect(x: 0, y: 100, width: 40, height: 16), in: textView)
        let laidOut = try #require(panel.laidOutContentHeightForTests, sourceLocation: sourceLocation)
        let shown = try #require(panel.panelHeightForTests, sourceLocation: sourceLocation)
        // Only when the panel is not clamped to its scrolling ceiling: at the ceiling the window is deliberately
        // capped below what the full, unclamped content would need, and the body's own scroller reaches the rest.
        guard laidOut < HoverPanelSizing.maxHeight else { return }
        #expect(abs(shown - laidOut) < 1, "shown \(shown) vs laid out \(laidOut)", sourceLocation: sourceLocation)
    }

    @Test func aDeclarationOnlyDocumentHasNoWastedSpace() throws {
        let document = HoverDocument(
            declaration: codeAttributed("struct CameraConfiguration"), chipBackground: .textBackgroundColor)
        try assertNoWastedSpace(document)
    }

    @Test func aDeclarationAndSummaryDocumentHasNoWastedSpace() throws {
        let document = HoverDocument(
            declaration: codeAttributed("struct CameraConfiguration"),
            summary: prose("A value type describing how a capture session should be configured."),
            chipBackground: .textBackgroundColor)
        try assertNoWastedSpace(document)
    }

    @Test func aFullDocumentWithParametersAndCandidatesHasNoWastedSpace() throws {
        let document = HoverDocument(
            declaration: codeAttributed("func configure(session: CaptureSession, retries: Int) -> Bool"),
            summary: prose("Configures a capture session."),
            discussion: prose("Retries the configuration up to `retries` times before giving up."),
            parameters: [
                HoverDocument.Field(name: "session", text: prose("The session to configure.")),
                HoverDocument.Field(name: "retries", text: prose("How many times to retry."))
            ],
            returns: prose("Whether the configuration succeeded."),
            provenance: .languageServer,
            extraCandidates: [
                HoverDocument.Candidate(
                    declaration: codeAttributed("func configure(session: CaptureSession) -> Bool"),
                    summary: prose("An older overload kept for source compatibility."))
            ],
            chipBackground: .textBackgroundColor)
        try assertNoWastedSpace(document)
    }

    /// A regression test for the footer's own removal: the user found the provenance line unnecessary chrome, and
    /// it no longer renders even when ``HoverDocument/provenance`` carries a real tier -- the panel simply never
    /// builds a footer view at all any more, so there is nothing to check it against besides the fixtures above
    /// laying out with no wasted space regardless of what `provenance` is set to.
    @Test func provenanceStillHasNoFooterFootprint() throws {
        let withProvenance = HoverDocument(
            declaration: codeAttributed("struct CameraConfiguration"), provenance: .languageServer,
            chipBackground: .textBackgroundColor)
        let withoutProvenance = HoverDocument(
            declaration: codeAttributed("struct CameraConfiguration"), provenance: .unknown,
            chipBackground: .textBackgroundColor)

        let panelWith = HoverDocPanel()
        panelWith.show(
            document: withProvenance, anchorRect: NSRect(x: 0, y: 100, width: 40, height: 16),
            in: makeHostTextView())
        let panelWithout = HoverDocPanel()
        panelWithout.show(
            document: withoutProvenance, anchorRect: NSRect(x: 0, y: 100, width: 40, height: 16),
            in: makeHostTextView())

        let heightWith = try #require(panelWith.laidOutContentHeightForTests)
        let heightWithout = try #require(panelWithout.laidOutContentHeightForTests)
        #expect(abs(heightWith - heightWithout) < 1)
    }
}
