import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The panel's window is sized to exactly its laid-out content, with no wasted space, across fixtures of
/// increasing shape.
@MainActor
struct HoverDocPanelTests {
    @MainActor
    private final class WindowRetainer {
        private var windows: [NSWindow] = []
        func append(_ window: NSWindow) { windows.append(window) }
    }

    private let retainedWindows = WindowRetainer()

    /// A text view in a real, off-screen window: the panel attaches to a window and reads its screen.
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

    /// Asserts the panel's height matches its laid-out content height for `document`, within a point.
    private func assertNoWastedSpace(
        _ document: HoverDocument, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let panel = HoverDocPanel()
        let textView = makeHostTextView()
        panel.show(document: document, anchorRect: NSRect(x: 0, y: 100, width: 40, height: 16), in: textView)
        let laidOut = try #require(panel.laidOutContentHeightForTests, sourceLocation: sourceLocation)
        let shown = try #require(panel.panelHeightForTests, sourceLocation: sourceLocation)
        // At the ceiling the window is capped on purpose and the body scrolls.
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

    /// A provenance adds nothing to the panel's height: the panel draws no footer.
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
