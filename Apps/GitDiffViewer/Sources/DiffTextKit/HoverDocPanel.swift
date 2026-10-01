package import AppKit
package import DiffRendering
import Foundation
import os

/// The hover panel's sizing rules: a fixed width, a height that hugs its content up to a ceiling past which the
/// body scrolls, and an origin under the hovered identifier that flips above it near the screen's bottom.
package enum HoverPanelSizing {
    package static let width: CGFloat = 440
    /// The panel's smallest height; taller content up to ``maxHeight`` is hugged exactly.
    package static let minHeight: CGFloat = 40
    package static let maxHeight: CGFloat = 420

    /// The panel's height for `contentHeight` of measured content, between ``minHeight`` and ``maxHeight``, and
    /// whether the body must scroll to show the rest.
    package static func clampedHeight(forContentHeight contentHeight: CGFloat) -> (height: CGFloat, scrolls: Bool) {
        guard contentHeight > maxHeight else { return (max(contentHeight, minHeight), false) }
        return (maxHeight, true)
    }

    /// The body's height within ``maxHeight`` once the rest of the panel takes `chromeHeight`, never under 60pt.
    package static func bodyHeightBudget(chromeHeight: CGFloat) -> CGFloat {
        max(maxHeight - chromeHeight, 60)
    }

    /// The panel's screen origin: below `anchorRect` and left-aligned with it, flipped above it when it would run
    /// off `screenFrame`'s bottom, and clamped horizontally inside `screenFrame`.
    package static func origin(anchorRect: NSRect, panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let belowY = anchorRect.minY - panelSize.height
        let y = belowY >= screenFrame.minY ? belowY : anchorRect.maxY
        var x = anchorRect.minX
        x = min(x, screenFrame.maxX - panelSize.width)
        x = max(x, screenFrame.minX)
        return NSPoint(x: x, y: y)
    }
}

/// The hover panel's spacing and padding scale, shared by every slot.
package enum HoverPanelMetrics {
    /// The content stack's own inset from the panel's edge, on every side.
    package static let edgeInset: CGFloat = 12
    /// Between two sibling sections of the content stack.
    package static let sectionSpacing: CGFloat = 10
    /// Between a section header and its content, tighter than ``sectionSpacing`` so the header reads as attached.
    package static let headerToContentSpacing: CGFloat = 4
    /// A declaration chip's inset between its background and its code.
    package static let chipHorizontalPadding: CGFloat = 8
    package static let chipVerticalPadding: CGFloat = 6
    /// The chip's own corner radius, a notch smaller than the panel's own so it reads as set into the glass.
    package static let chipCornerRadius: CGFloat = 4
    /// The panel's corner radius, which its background, glass or popover material, is clipped to.
    package static let panelCornerRadius: CGFloat = 8
}

/// The rich hover panel: an arrow-less, non-activating child window styled like Xcode's Quick Help, sized to its
/// content and anchored under the hovered identifier. A documented symbol reads as Quick Help does: its name as a
/// title, its abstract, its declaration in a box, a divider, then the discussion under an Overview heading, block by
/// block, scrolling past the panel's height. A symbol with nothing but its declaration shows the declaration alone.
@MainActor
package final class HoverDocPanel {
    /// Whether the panel is currently on screen.
    package private(set) var isVisible = false
    /// Whether the pointer is over the panel, so leaving the pane for the panel does not dismiss it.
    package private(set) var pointerIsInside = false
    /// Told each time the pointer comes over the panel (true) or leaves it (false).
    package var onPointerInsideChange: (@MainActor (Bool) -> Void)?

    private var panel: NSPanel?
    private weak var attachedWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    /// The delegate of every text view the panel builds; `NSTextView.delegate` is weak, so the panel keeps it.
    let linkDelegate: HoverLinkDelegate
    private let titleLabel = HoverDocPanel.makeTitleLabel()
    private let summaryView: NSTextView
    private let declarationView: NSTextView
    /// The declaration's backing, filled with ``HoverDocument/chipBackground``.
    private let declarationChip = HoverDocPanel.makeChip()
    /// Sets the head (title, abstract, declaration) apart from what follows it.
    private let headDivider = HoverDocPanel.makeDivider()
    /// The discussion's blocks not built yet: a long discussion builds what the panel shows, and the rest as the body
    /// scrolls towards it.
    var pendingDiscussion: PendingDiscussion?
    /// The body's top-level block views, kept from one document to the next so a reused panel reconfigures them
    /// rather than removing them from the stack and building new ones.
    var blockSlots = HoverBlockSlots()
    let bodyDocument = HoverFlippedView()
    let bodyScrollView = NSScrollView()
    /// Observes the body's scrolling, to build the blocks it scrolls towards.
    private var bodyScrollObserver: (any NSObjectProtocol)?
    private let parametersGrid = NSGridView(numberOfColumns: 2, rows: 0)
    private let parametersHeader = HoverDocPanel.makeSectionLabel("Parameters")
    private let returnsHeader = HoverDocPanel.makeSectionLabel("Returns")
    private let returnsView: NSTextView
    private let diagnosticsStack = NSStackView()
    /// Quick Help's "Open in Developer Documentation", for a system symbol.
    private let documentationLinkView: NSTextView
    private let candidatesStack = NSStackView()
    private let contentStack = NSStackView()
    /// Holds the content stack inside whichever background ``HoverPanelMaterial`` makes, and tracks the pointer.
    private let contentHost = NSView()
    /// What the panel's background is made of, as last built; nil before the panel is.
    private(set) var material: HoverPanelMaterial?

    // `NSTextView` has no intrinsic size, so the text slots need explicit heights, recomputed by every render. The
    // declaration's is its text view's, not its chip's: the chip pads the text view on every edge, so a chip of zero
    // height would conflict with the padding.
    private var summaryHeight: NSLayoutConstraint?
    private var declarationHeight: NSLayoutConstraint?
    private var bodyHeight: NSLayoutConstraint?
    private var returnsHeight: NSLayoutConstraint?
    private var documentationLinkHeight: NSLayoutConstraint?

    /// Whether ``show(document:anchorRect:in:)`` orders the panel's window in; a panel that does not is shown in
    /// every other respect, sized and placed, for tests that must put no window on screen.
    private let ordersWindowIn: Bool

    /// - Parameters:
    ///   - openLink: Opens a clicked link that ``HoverDocument/openableURL(forLink:)`` allows; a refused link reaches
    ///     nothing, not even `NSTextView`'s own fallback.
    ///   - ordersWindowIn: Whether showing orders the panel's window in; false only in tests.
    package init(
        openLink: @escaping @MainActor (URL) -> Void = HoverDocPanel.openInDefaultApp, ordersWindowIn: Bool = true
    ) {
        self.ordersWindowIn = ordersWindowIn
        let linkDelegate = HoverLinkDelegate(open: openLink)
        self.linkDelegate = linkDelegate
        summaryView = HoverDocPanel.makeProseTextView(linkDelegate: linkDelegate)
        declarationView = HoverDocPanel.makeCodeTextView(linkDelegate: linkDelegate)
        returnsView = HoverDocPanel.makeProseTextView(linkDelegate: linkDelegate)
        documentationLinkView = HoverDocPanel.makeProseTextView(linkDelegate: linkDelegate)
        Self.liveCount += 1
    }

    isolated deinit {
        Self.liveCount -= 1
        if let bodyScrollObserver { NotificationCenter.default.removeObserver(bodyScrollObserver) }
    }

    /// How many panels are alive; for tests that check the panes build theirs only when hovered and release them.
    package private(set) static var liveCount = 0

    /// Opens `url` in the user's default app for it, logging a failure.
    package static func openInDefaultApp(_ url: URL) {
        guard !NSWorkspace.shared.open(url) else { return }
        logger.error("Could not open the hover link \(url.absoluteString, privacy: .private)")
    }

    private static let logger = Logger(subsystem: "fr.gcqd.GitDiffViewer", category: "HoverDocPanel")

    /// Shows (or repositions and re-renders, if already shown) the panel for `document` on a background made of
    /// `material`, anchored at `anchorRect` (in `textView`'s own coordinates) and attached as a child window of
    /// `textView`'s own window, whose appearance it matches.
    package func show(
        document: HoverDocument, material: HoverPanelMaterial = .liquidGlass, anchorRect: NSRect,
        in textView: NSTextView
    ) {
        guard let hostWindow = textView.window, let screen = hostWindow.screen else { return }
        let (panel, size) = prepare(document: document, material: material, appearance: textView.effectiveAppearance)

        setOrigin(forAnchorRect: anchorRect, panelSize: size, in: textView, hostWindow: hostWindow, screen: screen)

        if !isVisible {
            if ordersWindowIn {
                hostWindow.addChildWindow(panel, ordered: .above)
                panel.orderFront(nil)
            }
            isVisible = true
        }
        attachedWindow = hostWindow
    }

    /// Builds and sizes the same panel as ``show(document:anchorRect:in:)`` without ordering a window on screen.
    package func prepareOffscreenForTests(
        document: HoverDocument, material: HoverPanelMaterial = .liquidGlass, appearance: NSAppearance
    ) {
        _ = prepare(document: document, material: material, appearance: appearance)
    }

    private func prepare(
        document: HoverDocument, material: HoverPanelMaterial, appearance: NSAppearance
    ) -> (NSPanel, NSSize) {
        let panel = panel ?? makePanel()
        self.panel = panel
        if self.material != material {
            self.material = material
            panel.contentView = Self.makeBackground(material, around: contentHost)
        }
        panel.appearance = appearance
        let contentHeight = render(document)
        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: contentHeight)
        bodyScrollView.hasVerticalScroller = scrolls
        let size = NSSize(width: HoverPanelSizing.width, height: height)
        panel.setContentSize(size)
        // The window's shadow follows its content's rounded alpha, which a new size or background changes.
        panel.invalidateShadow()
        return (panel, size)
    }

    /// Moves a visible panel to `anchorRect`, in `textView`'s coordinates, without re-rendering or resizing it; a
    /// no-op when the panel is not showing.
    package func reposition(anchorRect: NSRect, in textView: NSTextView) {
        guard isVisible, let panel, let hostWindow = textView.window, let screen = hostWindow.screen else { return }
        setOrigin(
            forAnchorRect: anchorRect, panelSize: panel.frame.size, in: textView, hostWindow: hostWindow,
            screen: screen)
    }

    /// Converts `anchorRect` to screen coordinates and places the panel per ``HoverPanelSizing``.
    private func setOrigin(
        forAnchorRect anchorRect: NSRect, panelSize: NSSize, in textView: NSTextView, hostWindow: NSWindow,
        screen: NSScreen
    ) {
        guard let panel else { return }
        let screenAnchor = hostWindow.convertToScreen(textView.convert(anchorRect, to: nil))
        let origin = HoverPanelSizing.origin(
            anchorRect: screenAnchor, panelSize: panelSize, screenFrame: screen.visibleFrame)
        panel.setFrameOrigin(origin)
    }

    /// For tests: the content stack's fitting height after a layout pass; nil before the panel is first shown.
    package var laidOutContentHeightForTests: CGFloat? {
        guard let panel else { return nil }
        panel.contentView?.layoutSubtreeIfNeeded()
        return contentStack.fittingSize.height
    }

    /// For tests: the panel's height as ``show(document:anchorRect:in:)`` last sized it; nil before it is first shown.
    package var panelHeightForTests: CGFloat? { panel?.frame.size.height }

    /// For tests: the root of the panel's view hierarchy, its background; nil before it is first shown.
    package var contentViewForTests: NSView? { panel?.contentView }

    /// For tests: the panel's window; nil before it is first shown.
    package var windowForTests: NSWindow? { panel }

    /// Hides the panel and detaches it from its host window; a no-op when it is not showing.
    package func close() {
        guard let panel, isVisible else { return }
        if ordersWindowIn {
            attachedWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        isVisible = false
        pointerIsInside = false
        attachedWindow = nil
    }

    // MARK: Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: HoverPanelSizing.width, height: HoverPanelSizing.minHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = HoverPanelMetrics.sectionSpacing
        contentStack.edgeInsets = NSEdgeInsets(
            top: HoverPanelMetrics.edgeInset, left: HoverPanelMetrics.edgeInset, bottom: HoverPanelMetrics.edgeInset,
            right: HoverPanelMetrics.edgeInset)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        configureBody()

        parametersGrid.rowSpacing = 4
        parametersGrid.columnSpacing = 8

        diagnosticsStack.orientation = .vertical
        diagnosticsStack.alignment = .leading
        diagnosticsStack.spacing = 4

        candidatesStack.orientation = .vertical
        candidatesStack.alignment = .leading
        candidatesStack.spacing = 6

        Self.configureChip(declarationChip, around: declarationView)

        for view in [
            titleLabel, summaryView, declarationChip, headDivider, bodyScrollView, parametersHeader, parametersGrid,
            returnsHeader, returnsView, candidatesStack, diagnosticsStack, documentationLinkView
        ] {
            contentStack.addArrangedSubview(view)
            let width = view.widthAnchor.constraint(equalToConstant: HoverPanelSizing.width - 24)
            // The grid's columns set its width when it has no rows: its own gives way to them rather than conflict.
            if view === parametersGrid { width.priority = .required - 1 }
            width.isActive = true
        }
        contentStack.setCustomSpacing(HoverPanelMetrics.headerToContentSpacing, after: titleLabel)
        contentStack.setCustomSpacing(HoverPanelMetrics.headerToContentSpacing, after: parametersHeader)
        contentStack.setCustomSpacing(HoverPanelMetrics.headerToContentSpacing, after: returnsHeader)

        summaryHeight = summaryView.heightAnchor.constraint(equalToConstant: 0)
        summaryHeight?.isActive = true
        declarationHeight = declarationView.heightAnchor.constraint(equalToConstant: 0)
        declarationHeight?.isActive = true
        bodyHeight = bodyScrollView.heightAnchor.constraint(equalToConstant: 0)
        bodyHeight?.isActive = true
        returnsHeight = returnsView.heightAnchor.constraint(equalToConstant: 0)
        returnsHeight?.isActive = true
        documentationLinkHeight = documentationLinkView.heightAnchor.constraint(equalToConstant: 0)
        documentationLinkHeight?.isActive = true

        contentHost.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentHost.bottomAnchor)
        ])

        // On the host, which moves from one background to the next, so a change of material keeps the tracking.
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        contentHost.addTrackingArea(area)
        trackingArea = area
        return panel
    }

    /// The discussion's scrolling body: a flipped document holding the blocks, which builds the blocks it scrolls to.
    private func configureBody() {
        bodyScrollView.documentView = bodyDocument
        bodyScrollView.contentView.postsBoundsChangedNotifications = true
        bodyScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: bodyScrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bodyDidScroll() }
        }
        bodyScrollView.drawsBackground = false
        bodyScrollView.hasVerticalScroller = false
        // The blocks are laid out at the panel's inner width, so the scroller floats over them: a legacy one, as with a
        // mouse attached, would take 15 pt of the width the blocks were made for and hide the end of each line.
        bodyScrollView.scrollerStyle = .overlay
        bodyScrollView.borderType = .noBorder
        bodyScrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: Rendering

    /// Renders `document` into every slot and sizes them, returning the content height the panel is sized from. The
    /// height comes from `contentStack`'s own fitting size, so sizing and layout never disagree.
    private func render(_ document: HoverDocument) -> CGFloat {
        let innerWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        let chipInnerWidth = innerWidth - 2 * HoverPanelMetrics.chipHorizontalPadding
        let hasDiscussion = !document.discussion.isEmpty
        let hasFields = !document.parameters.isEmpty || document.returns != nil
        // The title names what the documentation is about; over a bare declaration it would only repeat it.
        let hasDocumentation = document.summary != nil || hasDiscussion || hasFields

        titleLabel.stringValue = document.title ?? ""
        titleLabel.isHidden = !hasDocumentation || document.title == nil

        let summary = document.summary ?? NSAttributedString()
        summaryView.textStorage?.setAttributedString(summary)
        summaryView.isHidden = document.summary == nil
        summaryHeight?.constant = summaryView.isHidden ? 0 : Self.measuredHeight(of: summary, width: innerWidth)

        let declaration = document.declaration ?? NSAttributedString()
        declarationView.textStorage?.setAttributedString(declaration)
        declarationChip.isHidden = document.declaration == nil
        declarationChip.fillColor = document.chipBackground ?? .clear
        declarationHeight?.constant =
            declarationChip.isHidden ? 0 : Self.measuredHeight(of: declaration, width: chipInnerWidth)

        // The relationships are read from the declaration: over a bare declaration they would only repeat it.
        let bodyBlocks = Self.bodyBlocks(for: document, showsRelationships: hasDocumentation)
        let hasHead = !titleLabel.isHidden || !summaryView.isHidden || !declarationChip.isHidden
        headDivider.isHidden = !(hasHead && (!bodyBlocks.isEmpty || hasFields))

        renderParameters(document.parameters)
        parametersHeader.isHidden = document.parameters.isEmpty
        parametersGrid.isHidden = document.parameters.isEmpty

        let returns = document.returns ?? NSAttributedString()
        returnsView.textStorage?.setAttributedString(returns)
        returnsHeader.isHidden = document.returns == nil
        returnsView.isHidden = document.returns == nil
        returnsHeight?.constant = returnsView.isHidden ? 0 : Self.measuredHeight(of: returns, width: innerWidth)

        renderCandidates(document.extraCandidates, chipBackground: document.chipBackground)
        candidatesStack.isHidden = document.extraCandidates.isEmpty

        renderDiagnostics(document.diagnostics)
        diagnosticsStack.isHidden = document.diagnostics.isEmpty

        let link = document.documentationURL.map(Self.documentationLink(to:)) ?? NSAttributedString()
        documentationLinkView.textStorage?.setAttributedString(link)
        documentationLinkView.isHidden = document.documentationURL == nil
        documentationLinkHeight?.constant =
            documentationLinkView.isHidden ? 0 : Self.measuredHeight(of: link, width: innerWidth)

        renderDiscussion(bodyBlocks, chipBackground: document.chipBackground, width: innerWidth)
        bodyScrollView.isHidden = bodyBlocks.isEmpty
        let bodyFullHeight = bodyScrollView.isHidden ? 0 : blockSlots.contentHeight
        // The scroll view keeps its zero-size document view unless we give it the blocks' measured bounds.
        bodyDocument.setFrameSize(NSSize(width: innerWidth, height: bodyFullHeight))
        bodyScrollView.contentView.scroll(to: .zero)
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
        bodyHeight?.constant = 0
        contentStack.layoutSubtreeIfNeeded()
        let chromeHeight = contentStack.fittingSize.height

        // Budgeted against the rest of the panel, so a long body never outgrows the clamped window.
        let budget = HoverPanelSizing.bodyHeightBudget(chromeHeight: chromeHeight)
        bodyHeight?.constant = bodyScrollView.isHidden ? 0 : min(bodyFullHeight, budget)

        return bodyScrollView.isHidden ? chromeHeight : chromeHeight + bodyFullHeight
    }
}

// MARK: - Slot rendering, measurement, and view factories
// Kept outside the class body so it stays under `type_body_length`.
extension HoverDocPanel {
    fileprivate func renderParameters(_ parameters: [HoverDocument.Field]) {
        while parametersGrid.numberOfRows > 0 {
            let row = parametersGrid.row(at: parametersGrid.numberOfRows - 1)
            // Removing a row leaves its cells' views in the grid, unplaced: they go with it.
            let views = (0 ..< row.numberOfCells).compactMap { row.cell(at: $0).contentView }
            parametersGrid.removeRow(at: parametersGrid.numberOfRows - 1)
            views.forEach { $0.removeFromSuperview() }
        }
        let nameLabels = parameters.map { parameter in
            let label = NSTextField(labelWithString: parameter.name)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .labelColor
            return label
        }
        let nameColumnWidth = nameLabels.map { ceil($0.intrinsicContentSize.width) }.max() ?? 0
        // The descriptions wrap at the width their column has once the names take theirs, so their height counts
        // every line they are laid out on.
        let textColumnWidth =
            HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset - nameColumnWidth - parametersGrid.columnSpacing
        for (parameter, nameLabel) in zip(parameters, nameLabels) {
            let textLabel = NSTextField(labelWithAttributedString: parameter.text)
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.preferredMaxLayoutWidth = max(textColumnWidth, 1)
            parametersGrid.addRow(with: [nameLabel, textLabel])
        }
        // The names' column is as wide as the widest name, and the text's takes the rest of the grid's width: sized
        // to their content alone, the two columns would share that rest in no set way.
        parametersGrid.column(at: 0).width = parameters.isEmpty ? NSGridView.sizedForContent : nameColumnWidth
    }

    /// Rebuilds the candidates group: a chip per declaration and a prose row per summary, each sized to its text.
    fileprivate func renderCandidates(_ candidates: [HoverDocument.Candidate], chipBackground: NSColor?) {
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let innerWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        let chipInnerWidth = innerWidth - 2 * HoverPanelMetrics.chipHorizontalPadding
        // A hairline rule sets the candidates apart from the main declaration's body.
        if !candidates.isEmpty {
            candidatesStack.addArrangedSubview(HoverDocPanel.makeCandidatesSeparator())
        }
        for candidate in candidates where candidate.declaration != nil || candidate.summary != nil {
            if let declaration = candidate.declaration {
                let view = HoverDocPanel.makeCodeTextView(linkDelegate: linkDelegate)
                view.textStorage?.setAttributedString(declaration)
                let chip = HoverDocPanel.makeChip()
                Self.configureChip(chip, around: view)
                chip.fillColor = chipBackground ?? .clear
                let rowHeight =
                    Self.measuredHeight(of: declaration, width: chipInnerWidth)
                    + 2 * HoverPanelMetrics.chipVerticalPadding
                candidatesStack.addArrangedSubview(chip)
                chip.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                chip.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
            if let summary = candidate.summary {
                let view = HoverDocPanel.makeProseTextView(linkDelegate: linkDelegate)
                view.textStorage?.setAttributedString(summary)
                let rowHeight = Self.measuredHeight(of: summary, width: innerWidth)
                candidatesStack.addArrangedSubview(view)
                view.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                view.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
        }
    }

    fileprivate func renderDiagnostics(_ diagnostics: [HoverDocument.DiagnosticEntry]) {
        diagnosticsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in diagnostics {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            let bar = NSBox()
            bar.boxType = .custom
            bar.fillColor = entry.severity.tint
            bar.borderWidth = 0
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 3).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 14).isActive = true
            let label = NSTextField(labelWithString: "\(entry.message) — \(entry.tool)")
            label.lineBreakMode = .byWordWrapping
            row.addArrangedSubview(bar)
            row.addArrangedSubview(label)
            diagnosticsStack.addArrangedSubview(row)
        }
    }

    /// The height `text` lays out to at `width`, measured on a throwaway TextKit 2 stack so no slot's view is touched.
    static func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(text)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return layoutManager.usageBoundsForTextContainer.height
    }

    /// A declaration chip: an `NSBox`, whose fill and border colors resolve at draw time and so follow appearance
    /// changes, unlike a layer's baked `CGColor`s.
    static func makeChip() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = HoverPanelMetrics.chipCornerRadius
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// Pins `textView` inside `chip`, inset by the chip padding on every edge.
    static func configureChip(_ chip: NSBox, around textView: NSTextView) {
        chip.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(
                equalTo: chip.leadingAnchor, constant: HoverPanelMetrics.chipHorizontalPadding),
            textView.trailingAnchor.constraint(
                equalTo: chip.trailingAnchor, constant: -HoverPanelMetrics.chipHorizontalPadding),
            textView.topAnchor.constraint(equalTo: chip.topAnchor, constant: HoverPanelMetrics.chipVerticalPadding),
            textView.bottomAnchor.constraint(
                equalTo: chip.bottomAnchor, constant: -HoverPanelMetrics.chipVerticalPadding)
        ])
    }

    /// A selectable, read-only text view whose link clicks go through `linkDelegate`.
    static func makeCodeTextView(linkDelegate: HoverLinkDelegate) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.delegate = linkDelegate
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    /// A selectable, read-only text view that wraps to its width, whose link clicks go through `linkDelegate`.
    static func makeProseTextView(linkDelegate: HoverLinkDelegate) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.delegate = linkDelegate
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    /// Quick Help's link to a system symbol's page in Apple's developer documentation, opened as any link of the
    /// panel is, through ``HoverLinkDelegate``.
    static func documentationLink(to url: URL) -> NSAttributedString {
        NSAttributedString(
            string: "Open in Developer Documentation",
            attributes: [.font: NSFont.systemFont(ofSize: HoverTypography.bodySize), .link: url])
    }

    fileprivate static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}

extension HoverDocPanel {
    /// `NSTrackingArea` calls its owner by selector, so the Objective-C names are pinned.
    @objc(mouseEntered:) fileprivate func mouseEntered(with event: NSEvent) { pointerEntered() }
    @objc(mouseExited:) fileprivate func mouseExited(with event: NSEvent) { pointerExited() }

    /// The pointer came over the panel: the testable core of its tracking area's `mouseEntered`.
    package func pointerEntered() {
        pointerIsInside = true
        onPointerInsideChange?(true)
    }

    /// The pointer left the panel: the testable core of its tracking area's `mouseExited`.
    package func pointerExited() {
        pointerIsInside = false
        onPointerInsideChange?(false)
    }

    /// The panel's frame in screen coordinates while it shows; nil otherwise.
    package var frameOnScreen: NSRect? { isVisible ? panel?.frame : nil }

    /// Whether `window` is the panel's own window, as for an event inside it.
    package func owns(_ window: NSWindow?) -> Bool {
        guard let window, let panel else { return false }
        return window === panel
    }

    /// A hairline separator sized to the panel's inner width, set ahead of the first candidate.
    fileprivate static func makeCandidatesSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: HoverPanelSizing.width - 24).isActive = true
        return box
    }
}

extension HoverDocument.DiagnosticEntry.Severity {
    fileprivate var tint: NSColor {
        switch self {
            case .note: .secondaryLabelColor
            case .warning: .systemOrange
            case .error: .systemRed
        }
    }
}

/// Opens a clicked link through `open` only when ``HoverDocument/openableURL(forLink:)`` allows it, and reports every
/// click handled: `NSTextView` opens any link its delegate leaves unhandled, whatever its scheme.
@MainActor
final class HoverLinkDelegate: NSObject, NSTextViewDelegate {
    private let open: @MainActor (URL) -> Void

    init(open: @escaping @MainActor (URL) -> Void) {
        self.open = open
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = HoverDocument.openableURL(forLink: link) {
            open(url)
        }
        return true
    }
}
