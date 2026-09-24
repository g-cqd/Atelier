import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A doc comment comes from the repository under review, so its links are attacker input: prose rendering keeps only
/// `https` links, and every text view the hover panel builds opens nothing else, whatever the document carries.
@MainActor
struct HoverLinkTests {
    /// A link value `NSTextView` can hand its delegate, other than an `https` URL.
    enum RefusedLink: CaseIterable, Sendable, CustomTestStringConvertible {
        case file
        case smb
        case http
        case customScheme
        case relativeURL
        case relativeString

        var value: Any {
            switch self {
                case .file: URL(filePath: "/etc/passwd")
                case .smb: URL(string: "smb://server/share") ?? URL(filePath: "/")
                case .http: URL(string: "http://example.com/guide") ?? URL(filePath: "/")
                case .customScheme: URL(string: "x-atelier-probe://open") ?? URL(filePath: "/")
                case .relativeURL: URL(string: "guide.html") ?? URL(filePath: "/")
                case .relativeString: "guide.html"
            }
        }

        var testDescription: String { "\(self)" }
    }

    @MainActor
    private final class OpenedLinks {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    @MainActor
    private final class WindowRetainer {
        private var windows: [NSWindow] = []
        func append(_ window: NSWindow) { windows.append(window) }
    }

    private let retainedWindows = WindowRetainer()
    private static let https = URL(string: "https://example.com/guide") ?? URL(filePath: "/")

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

    /// Text carrying a `file://` link, so the panel is exercised apart from prose rendering, which would drop it.
    private static func linkedProse(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        result.addAttribute(.link, value: URL(filePath: "/etc/passwd"), range: NSRange(location: 0, length: 4))
        return result
    }

    /// A document that fills every slot the panel has: declaration, body, parameters, returns and a candidate.
    private static let everySlot = HoverDocument(
        declaration: NSAttributedString(string: "func open(path: String) -> Bool"),
        summary: linkedProse("Opens a file."),
        discussion: [.paragraph(linkedProse("Reads it whole."))],
        parameters: [HoverDocument.Field(name: "path", text: linkedProse("Where the file lives."))],
        returns: linkedProse("Whether it opened."),
        extraCandidates: [
            HoverDocument.Candidate(
                declaration: NSAttributedString(string: "func open() -> Bool"), summary: linkedProse("An overload."))
        ],
        chipBackground: .textBackgroundColor)

    /// A panel showing ``everySlot`` whose opener records what it is asked to open.
    private func shownPanel(recordingInto opened: OpenedLinks) -> HoverDocPanel {
        let panel = HoverDocPanel(openLink: { opened.record($0) }, ordersWindowIn: false)
        panel.show(
            document: Self.everySlot, anchorRect: NSRect(x: 0, y: 100, width: 40, height: 16), in: makeHostTextView())
        return panel
    }

    /// Every view of `type` under `root`, walked with an explicit stack.
    private static func descendants<View: NSView>(of root: NSView, as type: View.Type) -> [View] {
        var found: [View] = []
        var pending = [root]
        while let view = pending.popLast() {
            if let match = view as? View { found.append(match) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }

    /// The URLs of every link in `text`, whether stored as a `URL` or a string.
    private static func links(in text: NSAttributedString) -> [URL] {
        var urls: [URL] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let url = value as? URL {
                urls.append(url)
            } else if let string = value as? String, let url = URL(string: string) {
                urls.append(url)
            }
        }
        return urls
    }

    @Test(arguments: [
        ("https://example.com/guide", true), ("HTTPS://example.com/guide", true), ("http://example.com/guide", false),
        ("file:///etc/passwd", false), ("smb://server/share", false), ("x-atelier-probe://open", false),
        ("guide.html", false)
    ])
    func `only an https link survives prose rendering, and a dropped link keeps its text`(
        link: String, survives: Bool
    ) throws {
        let content = HoverContent(markdown: "See [the guide](\(link)) first.", source: .docIndex)
        let summary = try #require(HoverDocument.build(from: content, palette: .system).summary)

        #expect(summary.string == "See the guide first.")
        // Case-folded: a URL's scheme is case-insensitive, and the parser may normalize it.
        #expect(
            Self.links(in: summary).map { $0.absoluteString.lowercased() } == (survives ? [link.lowercased()] : []))
    }

    @Test
    func `a refused link is dropped from every prose section of a built document`() throws {
        let markdown = """
            ```swift
            func open(path: String) -> Bool
            ```

            Opens [the file](file:///etc/passwd).

            Also see [the share](smb://server/share).

            - Parameters:
              - path: Read [this](x-atelier-probe://open) first.
            - Returns: Whether [it](file:///etc/hosts) opened.

            ---

            ```swift
            func open() -> Bool
            ```

            An [older](file:///etc/passwd) overload.
            """
        let document = HoverDocument.build(from: HoverContent(markdown: markdown, source: .docIndex), palette: .system)
        let sections = [
            try #require(document.summary),
            try #require(
                document.discussion.compactMap { if case .paragraph(let text) = $0 { text } else { nil } }.first),
            try #require(document.parameters.first?.text), try #require(document.returns),
            try #require(document.extraCandidates.first?.summary)
        ]

        for section in sections {
            #expect(Self.links(in: section).isEmpty, "\(section.string)")
        }
    }

    @Test(arguments: RefusedLink.allCases)
    func `a click on a refused link in any text view of a shown panel is handled without reaching the opener`(
        link: RefusedLink
    ) throws {
        let opened = OpenedLinks()
        let panel = shownPanel(recordingInto: opened)
        let textViews = Self.descendants(of: try #require(panel.contentViewForTests), as: NSTextView.self)

        // Declaration, abstract, the Overview heading, the discussion's paragraph, returns, and the candidate's
        // declaration and summary.
        #expect(textViews.count == 7)
        for textView in textViews {
            let delegate = try #require(textView.delegate)
            // `true` tells `NSTextView` the click is handled; anything else makes it open the link itself.
            #expect(delegate.textView?(textView, clickedOnLink: link.value, at: 0) == true)
        }
        #expect(opened.urls.isEmpty)
    }

    @Test
    func `a click on an https link in any text view of a shown panel reaches the opener`() throws {
        let opened = OpenedLinks()
        let panel = shownPanel(recordingInto: opened)
        let textViews = Self.descendants(of: try #require(panel.contentViewForTests), as: NSTextView.self)

        #expect(textViews.count == 7)
        for textView in textViews {
            let delegate = try #require(textView.delegate)
            #expect(delegate.textView?(textView, clickedOnLink: Self.https, at: 0) == true)
        }
        #expect(opened.urls == Array(repeating: Self.https, count: textViews.count))
    }

    /// Only a selectable field hands a link click to AppKit, so the labels, parameter descriptions among them, need no
    /// link delegate.
    @Test
    func `no text field of a shown panel is selectable, so a link in a parameter description cannot be clicked`()
        throws
    {
        let panel = shownPanel(recordingInto: OpenedLinks())
        let fields = Self.descendants(of: try #require(panel.contentViewForTests), as: NSTextField.self)
        let parameterDescription = fields.first { $0.stringValue == "Where the file lives." }

        #expect(parameterDescription != nil)
        #expect(fields.allSatisfy { !$0.isSelectable })
    }
}
