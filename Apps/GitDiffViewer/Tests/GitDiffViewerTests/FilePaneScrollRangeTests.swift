import AemiTesting
import AppKit
import DiffCore
import Observation
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// How far a file pane scrolls. By default it ends with its last line at the bottom, the pane's inset under it, and a
/// file shorter than the pane shows whole with nothing to scroll; when it scrolls past its end, it goes on until the
/// last line reaches the top. Either way its text view covers its text from the moment it shows, whatever TextKit has
/// laid out: a pane sized from TextKit's usage bounds while they were empty, or held only what TextKit had laid out,
/// cut its text off partway down and did not scroll to the rest.
@MainActor
@Suite(.mainActorLane)
struct FilePaneScrollRangeTests {
    @Test(arguments: PaneLayout.allCases, [true, false])
    func `a new file pane shows a short file whole, with nothing to scroll`(layout: PaneLayout, wrapsLines: Bool)
        throws
    {
        // Short enough for either pane of the stacked layout, half the window each.
        let sut = HostedPanes(showing: .lines(6), layout: layout, wrapsLines: wrapsLines)

        for pane in try sut.panes() {
            #expect(pane.textView.frame.height == pane.clip.bounds.height)
            #expect(try pane.bottom(ofRow: pane.lastRow) + pane.below <= pane.clip.bounds.height)
        }
    }

    @Test(arguments: PaneLayout.allCases, [true, false])
    func `scrolled to its end, a file pane shows its last line at the bottom, its text laid out or not`(
        layout: PaneLayout, wrapsLines: Bool
    ) async throws {
        let sut = HostedPanes(showing: .longLines(60), layout: layout, wrapsLines: wrapsLines)
        try await sut.alignSides()

        for pane in try sut.panes() {
            #expect(pane.textView.frame.height >= pane.rowsHeight)
        }
        sut.scrollToEnd()

        for pane in try sut.panes() {
            let bottom = try pane.bottom(ofRow: pane.lastRow)
            #expect(abs(pane.textView.frame.height - (bottom + pane.below)) < 1)
            #expect(bottom <= pane.clip.bounds.maxY)
        }
    }

    /// A long file, then a shorter one in the same pane, as the temporary tab shows the next file.
    @Test(arguments: PaneLayout.allCases, [true, false])
    func `a file pane that scrolls past its end scrolls its last line up to its top, however long its file`(
        layout: PaneLayout, wrapsLines: Bool
    ) throws {
        let sut = HostedPanes(showing: .lines(60), layout: layout, wrapsLines: wrapsLines, scrollsPastEnd: true)
        try sut.expectEachPaneScrollsItsLastLineToItsTop()

        sut.show(.lines(12))

        try sut.expectEachPaneScrollsItsLastLineToItsTop()
    }
}

/// Where a file pane shows the row the model asks for, as it asks for a file's first change when the file opens (book
/// DIFF-08), and the row a click in the minimap asks for.
@MainActor
@Suite(.mainActorLane)
struct FilePaneScrollToRowTests {
    @Test(arguments: PaneLayout.allCases, [true, false])
    func `a file opens with its first change three lines below the pane's top`(layout: PaneLayout, wrapsLines: Bool)
        async throws
    {
        let sut = HostedPanes(showing: .longLines(60, changedAt: 30), layout: layout, wrapsLines: wrapsLines)
        try await sut.alignSides()

        let row = try #require(sut.requestedRow)
        for pane in try sut.panes() {
            let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
            #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")
        }
    }

    /// The temporary tab shows the next file, and its first change, in the pane that showed the last one.
    @Test(arguments: PaneLayout.allCases, [true, false])
    func `a file shown in the pane of another opens with its first change three lines below the pane's top`(
        layout: PaneLayout, wrapsLines: Bool
    ) async throws {
        let sut = HostedPanes(showing: .lines(20), layout: layout, wrapsLines: wrapsLines)
        try await sut.alignSides()

        sut.show(.longLines(60, changedAt: 30))
        try await sut.alignSides()

        let row = try #require(sut.requestedRow)
        for pane in try sut.panes() {
            let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
            #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")
        }
    }

    @Test(arguments: [false, true])
    func `a file that fits its pane opens at its top, whole, though its change is at its end`(scrollsPastEnd: Bool)
        throws
    {
        let sut = HostedPanes(
            showing: .lines(12, changedAt: 11), layout: .inline, wrapsLines: true, scrollsPastEnd: scrollsPastEnd)

        let pane = try #require(try sut.panes().first)
        #expect(pane.clip.bounds.minY == 0)
        #expect(try pane.bottom(ofRow: pane.lastRow) + pane.below <= pane.clip.bounds.height)
    }

    /// Past the text a placement lays out above its row, TextKit places the row after its estimates of the rows above
    /// it, which the placement follows as the rows around the row are laid out; scrolled to its end, the pane ends at
    /// the last line wherever TextKit then puts it.
    @Test(arguments: [true, false])
    func `a change near the end of a long file opens three lines below the pane's top, the rows above not laid out`(
        wrapsLines: Bool
    ) throws {
        let sut = HostedPanes(showing: .longLines(600, changedAt: 540), layout: .inline, wrapsLines: wrapsLines)

        let row = try #require(sut.requestedRow)
        let pane = try #require(try sut.panes().first)
        #expect(pane.rendered.lineStarts[row] > RowPlacement.textLaidOutAbove)
        let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
        #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")

        sut.scrollToEnd()

        let end = try #require(try sut.panes().first)
        let bottom = try end.bottom(ofRow: end.lastRow)
        #expect(abs(end.textView.frame.height - (bottom + end.below)) < 1)
        #expect(bottom <= end.clip.bounds.maxY)
    }

    @Test
    func `a long file opened at a change near its end scrolls past its end until its last line reaches the top`()
        throws
    {
        let sut = HostedPanes(
            showing: .longLines(600, changedAt: 540), layout: .inline, wrapsLines: true, scrollsPastEnd: true)

        sut.scrollToBottom()

        let pane = try #require(try sut.panes().first)
        let lastLineTop = try pane.bottom(ofRow: pane.lastRow) - pane.lineHeight
        #expect(
            abs(lastLineTop - pane.clip.bounds.minY) < 1,
            "the last line is \(lastLineTop - pane.clip.bounds.minY) below the pane's top")
    }

    @Test
    func `a file a line taller than its pane opens scrolled to its change at its end`() throws {
        // Inline, the changed line takes two rows: with the insets, the text runs a line and a half past the pane.
        let lineHeight = DiffPalette.system.defaultLineHeight
        let count = Int(((HostedPanes.paneHeight - 2 * DiffPaneMetrics.containerInset) / lineHeight).rounded(.up))
        let sut = HostedPanes(showing: .lines(count, changedAt: count - 1), layout: .inline, wrapsLines: true)

        let pane = try #require(try sut.panes().first)
        #expect(pane.rowsHeight - pane.clip.bounds.height < 2 * lineHeight)
        #expect(pane.clip.bounds.minY > 0)
        #expect(pane.clip.bounds.maxY == pane.textView.frame.height)
    }

    @Test(arguments: PaneLayout.allCases, [true, false])
    func `a click in the minimap brings its row to the pane's middle`(layout: PaneLayout, wrapsLines: Bool)
        async throws
    {
        let sut = HostedPanes(showing: .longLines(60), layout: layout, wrapsLines: wrapsLines)
        try await sut.alignSides()

        sut.selectInMinimap(row: 30)

        for pane in try sut.panes() {
            let offset = try pane.top(ofRow: 30) + pane.lineHeight / 2 - pane.clip.bounds.midY
            #expect(abs(offset) < 1, "the row's middle is \(offset) below the pane's")
        }
    }
}

/// One file's panes, as the detail area lays them out.
enum PaneLayout: String, CaseIterable, CustomTestStringConvertible {
    case inline, sideBySide, stacked
    var testDescription: String { rawValue }
}

/// A file to show, and whether the model asks the pane to show its change.
struct PaneText {
    let rendered: RenderedDiff
    let asksForChange: Bool

    /// `count` short lines, one of them changed: the one at `changed`, which the model asks the pane to show, or, with
    /// none, the middle one.
    static func lines(_ count: Int, changedAt changed: Int? = nil) -> PaneText {
        render((1 ... count).map { "let value\($0) = \($0)" }, changedAt: changed)
    }

    /// `count` lines, every seventh long enough that TextKit, estimating it before laying it out, takes it for two
    /// lines, and wide enough to wrap in the pane.
    static func longLines(_ count: Int, changedAt changed: Int? = nil) -> PaneText {
        let tail = String(repeating: "long ", count: 32)
        return render(
            (1 ... count).map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" },
            changedAt: changed)
    }

    private static func render(_ lines: [String], changedAt changed: Int?) -> PaneText {
        var new = lines
        new[changed ?? lines.count / 2] = "let changed = true"
        let rendered = DiffRenderer.render(
            oldText: lines.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
            language: .plain)
        return PaneText(rendered: rendered, asksForChange: changed != nil)
    }
}

/// A file's panes, hosted as the detail area hosts them, in a window that is never ordered in. The model's request to
/// show the file's first change comes with the file, as it does when a file opens.
@MainActor
final class HostedPanes {
    static let paneHeight: CGFloat = 300

    private let window: NSWindow
    private let host: NSHostingView<Panes>
    private let layout: PaneLayout
    private let wrapsLines: Bool
    private let scrollsPastEnd: Bool
    /// The height of the tab bar over the panes (book TAB-09).
    private let underBars: CGFloat
    /// Keeps the two sides in step, on a clock ``alignSides()`` moves.
    private let controller: SplitPaneController
    private let clock = TestClock()
    private let taskProvider = TaskProviderSpy.tolerant()
    /// The old pane's share of the length, as the window stores it (book DIFF-01).
    private let ratio: Binding<Double>
    /// The row the model asked the panes to show, if any.
    private(set) var requestedRow: Int?

    /// `ratio` is where the window keeps its pane ratio; nil keeps one of the panes' own, starting even.
    init(
        showing text: PaneText, layout: PaneLayout, wrapsLines: Bool, scrollsPastEnd: Bool = false,
        size: NSSize = NSSize(width: 600, height: HostedPanes.paneHeight), underBars: CGFloat = 0,
        ratio: Binding<Double>? = nil, scrollSync: SplitPaneController.ScrollSync = .byRow
    ) {
        self.underBars = underBars
        let ratio = ratio ?? PaneRatioStore().binding
        self.ratio = ratio
        let controller = SplitPaneController(clock: clock, taskProvider: taskProvider)
        // As the split view sets it when it appears.
        controller.wrapsLines = wrapsLines
        controller.scrollSync = scrollSync
        self.layout = layout
        self.wrapsLines = wrapsLines
        self.scrollsPastEnd = scrollsPastEnd
        self.controller = controller
        requestedRow = Self.firstChange(of: text, in: layout)
        host = NSHostingView(
            rootView: Panes(
                text: text, request: requestedRow.map(ScrollRequest.init(row:)), layout: layout,
                wrapsLines: wrapsLines, scrollsPastEnd: scrollsPastEnd, controller: controller, underBars: underBars,
                ratio: ratio))
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        settle()
    }

    /// The row the model asks for when `text` opens in `layout`: its first change.
    private static func firstChange(of text: PaneText, in layout: PaneLayout) -> Int? {
        guard text.asksForChange else { return nil }
        return (layout == .inline ? text.rendered.unifiedChangeStarts : text.rendered.splitChangeStarts).first
    }

    /// Shows another file in the same panes, as the temporary tab does.
    func show(_ text: PaneText) {
        requestedRow = Self.firstChange(of: text, in: layout)
        host.rootView = Panes(
            text: text, request: requestedRow.map(ScrollRequest.init(row:)), layout: layout,
            wrapsLines: wrapsLines, scrollsPastEnd: scrollsPastEnd, controller: controller, underBars: underBars,
            ratio: ratio)
        settle()
    }

    /// Each pane's gutter, text view and minimap, the old side's first.
    func paneViews() -> [DiffPaneView] {
        subviews(of: DiffPaneView.self, in: host)
    }

    /// The divider between the two panes; nil inline.
    var divider: PaneDividerView? {
        subviews(of: PaneDividerView.self, in: host).first
    }

    /// Drags the divider `distance` points towards the new pane, in steps, and releases it.
    func dragDivider(by distance: CGFloat) throws {
        let divider = try #require(divider)
        let start = divider.convert(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
        let offset = { (moved: CGFloat) in
            divider.axis == .horizontal
                ? NSPoint(x: start.x + moved, y: start.y) : NSPoint(x: start.x, y: start.y - moved)
        }
        divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: start))
        for step in 1 ... 4 {
            divider.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: offset(distance * CGFloat(step) / 4)))
            settle()
        }
        divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: offset(distance)))
        settle()
    }

    /// Double-clicks the divider.
    func doubleClickDivider() throws {
        let divider = try #require(divider)
        let point = divider.convert(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
        for clickCount in 1 ... 2 {
            divider.mouseDown(with: try mouseEvent(.leftMouseDown, at: point, clickCount: clickCount))
            divider.mouseUp(with: try mouseEvent(.leftMouseUp, at: point, clickCount: clickCount))
        }
        settle()
    }

    /// What the window's content view hits at `point`, in the window's coordinates.
    func hit(at point: NSPoint) -> NSView? {
        host.hitTest(host.superview?.convert(point, from: nil) ?? point)
    }

    private func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
    }

    /// Lays out and displays what needs it, as the run loop does between two events.
    func settleNow() {
        settle()
    }

    /// The panes, the old side's first.
    func panes() throws -> [ShownPane] {
        let textViews = subviews(of: DiffPaneTextView.self, in: host)
        try #require(textViews.count == (layout == .inline ? 1 : 2))
        return try textViews.map { textView in
            let gutter = try #require(subviews(of: DiffGutterView.self, in: host).first { $0.source === textView })
            return ShownPane(
                textView: textView, clip: try #require(textView.enclosingScrollView?.contentView),
                rendered: try #require(gutter.rendered))
        }
    }

    /// Each pane's gutter and text view with the text it shows, the old side's first.
    func shownPanes() throws -> [AlignedPane] {
        try subviews(of: DiffPaneTextView.self, in: host)
            .map { textView in
                let gutter = try #require(subviews(of: DiffGutterView.self, in: host).first { $0.source === textView })
                return AlignedPane(gutter: gutter, textView: textView, rendered: try #require(gutter.rendered))
            }
    }

    var bounds: NSRect { host.bounds }

    /// The window's pixels as its layers hold them, which no view is asked to draw for.
    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }

    /// The pixels once every view has drawn again.
    func redrawnPixels() throws -> LayerPixels {
        redrawAll(in: host)
        window.displayIfNeeded()
        return try pixels()
    }

    /// Scrolls each pane to its end as the End key does, again as long as laying out what shows there moves its end.
    func scrollToEnd() {
        for _ in 0 ..< 2 {
            for textView in subviews(of: DiffPaneTextView.self, in: host) { textView.scrollToEndOfDocument(nil) }
            settle()
        }
    }

    /// Scrolls each pane as far down as it goes, past the end of its text when it scrolls past it, which scrolling to
    /// the end of the document does not.
    func scrollToBottom() {
        scrollToEnd()
        for textView in subviews(of: DiffPaneTextView.self, in: host) {
            guard let clip = textView.enclosingScrollView?.contentView else { continue }
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: textView.frame.height - clip.bounds.height))
            clip.enclosingScrollView?.reflectScrolledClipView(clip)
        }
        settle()
    }

    /// Lets the split view's alignment of the two sides' rows run, as it does once layout settles.
    func alignSides() async throws {
        guard layout != .inline else { return }
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: SplitPaneController.alignmentDebounce)
        try await taskProvider.waitForAllTasks()
        settle()
    }

    /// Clicks `row` in each pane's minimap.
    func selectInMinimap(row: Int) {
        for minimap in subviews(of: MinimapView.self, in: host) { minimap.onSelectRow(row) }
        settle()
    }

    func expectEachPaneScrollsItsLastLineToItsTop(sourceLocation: SourceLocation = #_sourceLocation) throws {
        for pane in try panes() {
            let lastLineTop = pane.rowsHeight - pane.below - pane.lineHeight
            let endOffset = pane.textView.frame.height - pane.clip.bounds.height
            #expect(abs(lastLineTop - endOffset) < 1, sourceLocation: sourceLocation)
        }
    }

    /// Lays out and displays what needs it, twice: a pass can leave the panes needing another, as a row placed in
    /// one is checked in the next.
    private func settle() {
        for _ in 0 ..< 2 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }
}

/// One pane as it shows: its text view, its clip view, and the text it shows.
@MainActor
struct ShownPane {
    let textView: NSTextView
    let clip: NSClipView
    let rendered: RenderedText

    var lineHeight: CGFloat { rendered.lineHeight }
    var lastRow: Int { rendered.rows.count - 1 }
    /// Where the pane's top shows in its text view: below the bars over it, which cover what lies above (TAB-09).
    var shownTop: CGFloat { clip.bounds.minY + clip.contentInsets.top }
    /// How tall what shows of the pane is, less what the bars over it cover.
    var shownHeight: CGFloat { clip.bounds.height - clip.contentInsets.top }
    /// Below the last row: any band of a gap at the end of the file, then the pane's inset.
    var below: CGFloat { rendered.bandBelow + DiffPaneMetrics.containerInset }
    /// The rows at one line each, with the insets and bands around them: the height of the text, never wrapped.
    var rowsHeight: CGFloat { textView.textContainerInset.height + rendered.unwrappedTextHeight + below }

    /// The top of `row`'s line in the text view, as TextKit laid it out to draw it.
    func top(ofRow row: Int) throws -> CGFloat {
        try fragment(ofRow: row).layoutFragmentFrame.minY + textView.textContainerOrigin.y
    }

    /// The bottom of `row`'s last line in the text view, as TextKit laid it out to draw it.
    func bottom(ofRow row: Int) throws -> CGFloat {
        try fragment(ofRow: row).layoutFragmentFrame.maxY + textView.textContainerOrigin.y
    }

    /// Whether TextKit has laid out `row`, rather than placed it after its estimates.
    func isLaidOut(row: Int) throws -> Bool {
        let layoutManager = try #require(textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let location = try #require(
            content.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]))
        return layoutManager.textLayoutFragment(for: location)?.state == .layoutAvailable
    }

    /// The row at the pane's top below its bars, and how far below the row's top that lies.
    func rowAtTop() throws -> (row: Int, offset: CGFloat) {
        let layoutManager = try #require(textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let origin = textView.textContainerOrigin.y
        let fragment = try #require(layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: shownTop - origin)))
        try #require(fragment.state == .layoutAvailable, "the pane's top is not laid out")
        let row = rendered.rowIndex(
            containing: content.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location))
        return (row, shownTop - (fragment.layoutFragmentFrame.minY + origin))
    }

    private func fragment(ofRow row: Int) throws -> NSTextLayoutFragment {
        let layoutManager = try #require(textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let location = try #require(
            content.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]))
        let fragment = try #require(layoutManager.textLayoutFragment(for: location))
        try #require(fragment.state == .layoutAvailable, "row \(row) is not laid out")
        return fragment
    }
}

/// One file's panes: the inline pane, or the two sides next to each other or one above the other.
struct Panes: View {
    let text: PaneText
    let request: ScrollRequest?
    let layout: PaneLayout
    let wrapsLines: Bool
    let scrollsPastEnd: Bool
    let controller: SplitPaneController
    /// The tab bar's height over the panes: both run beneath it side by side, the old one alone stacked, as the
    /// detail area lays them out.
    var underBars: CGFloat = 0
    /// The old pane's share of the length.
    var ratio: Binding<Double> = .constant(PaneSplit.evenRatio)

    var body: some View {
        switch layout {
            case .inline:
                if let unified = text.rendered.unified {
                    pane(unified, gutter: .dual, controller: nil, underBars: underBars)
                }
            case .sideBySide, .stacked:
                if let old = text.rendered.old, let new = text.rendered.new {
                    let isStacked = layout == .stacked
                    ResizablePanes(
                        axis: isStacked ? .vertical : .horizontal, ratio: ratio, covered: isStacked ? underBars : 0
                    ) {
                        pane(old, gutter: .old, controller: controller, underBars: underBars)
                    } trailing: {
                        pane(new, gutter: .new, controller: controller, underBars: isStacked ? 0 : underBars)
                    }
                }
        }
    }

    private func pane(
        _ rendered: RenderedText, gutter: GutterStyle, controller: SplitPaneController?, underBars: CGFloat
    ) -> DiffTextView {
        DiffTextView(
            rendered: rendered, gutter: gutter, wrapsLines: wrapsLines, scrollRequest: request,
            splitController: controller, scrollsPastEnd: scrollsPastEnd, underBars: underBars)
    }
}

/// A pane ratio kept outside the panes, as a window keeps its own, whose changes the panes observe.
@MainActor
@Observable
final class PaneRatioStore {
    var ratio = PaneSplit.evenRatio

    var binding: Binding<Double> {
        Binding(get: { self.ratio }, set: { self.ratio = $0 })
    }
}

/// Every view of `type` in `view`'s tree, `view` included, in the order they are laid out.
@MainActor
func subviews<View: NSView>(of type: View.Type, in view: NSView) -> [View] {
    let own: [View] = (view as? View).map { [$0] } ?? []
    return own + view.subviews.flatMap { subviews(of: type, in: $0) }
}
