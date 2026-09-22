package import AppKit
package import DiffRendering
import Foundation

/// The panel's fixed sizing rules, pulled out of ``HoverDocPanel`` itself so they are testable without an actual
/// window: a fixed width, a height that hugs its measured content up to a ceiling (past which only the body
/// scrolls), and where the panel opens relative to the hovered identifier, flipping above it when it would
/// otherwise run off the bottom of the screen.
package enum HoverPanelSizing {
    package static let width: CGFloat = 440
    /// A floor only for the degenerate case (a document with nothing to show at all, not even a declaration):
    /// real content is never clamped up to this -- see ``clampedHeight(forContentHeight:)``. Xcode's own Quick
    /// Help panel has no fixed minimum either; a panel that hugs a two-line declaration and a one-line footer
    /// should read as exactly that, not pad itself out to a floor sized for a full doc with parameters and a
    /// multi-paragraph discussion.
    package static let minHeight: CGFloat = 40
    package static let maxHeight: CGFloat = 420

    /// The panel's own height for `contentHeight` of measured content, and whether the body needs its own inner
    /// scroll to show the rest: the chrome around it (header, declaration, parameters, footer) is always shown in
    /// full, only the body's prose ever scrolls. Hugs `contentHeight` exactly between the degenerate floor and the
    /// ceiling -- no fixed minimum beyond that floor, so a short answer (a declaration and a footer, say) gets a
    /// short panel instead of empty space padded out to what a full one would need.
    package static func clampedHeight(forContentHeight contentHeight: CGFloat) -> (height: CGFloat, scrolls: Bool) {
        guard contentHeight > maxHeight else { return (max(contentHeight, minHeight), false) }
        return (maxHeight, true)
    }

    /// The body's own height budget within `maxHeight`, once every other chrome slot (declaration, parameters,
    /// returns, candidates, diagnostics, footer, and the spacing between them) has taken `chromeHeight`: what is
    /// left over, floored at 60pt so the body is never squeezed to nothing even when the chrome alone already
    /// exceeds the cap. Without this floor the body's own height constraint would ask for more room than the
    /// clamped window actually has, and the excess would be clipped outside the window instead of reachable by
    /// the body's own scroll.
    package static func bodyHeightBudget(chromeHeight: CGFloat) -> CGFloat {
        max(maxHeight - chromeHeight, 60)
    }

    /// The panel's origin, in screen coordinates: below and left-aligned with `anchorRect` when it fits on
    /// `screenFrame`, flipped above the identifier when it would run off the bottom, and clamped horizontally so
    /// it never runs off either side.
    package static func origin(anchorRect: NSRect, panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let belowY = anchorRect.minY - panelSize.height
        let y = belowY >= screenFrame.minY ? belowY : anchorRect.maxY
        var x = anchorRect.minX
        x = min(x, screenFrame.maxX - panelSize.width)
        x = max(x, screenFrame.minX)
        return NSPoint(x: x, y: y)
    }
}

/// The panel's own spacing and padding scale, gathered in one place so every slot agrees on the same rhythm
/// instead of each guessing its own constant: read together, tight around a declaration chip, a little more
/// breathing room between unrelated sections, and a section header sitting close to the content it introduces
/// rather than floating in its own paragraph.
package enum HoverPanelMetrics {
    /// The content stack's own inset from the panel's edge, on every side.
    package static let edgeInset: CGFloat = 12
    /// Between two sibling sections at the content stack's own top level (a declaration and the body, a
    /// candidates group and the diagnostics list, ...).
    package static let sectionSpacing: CGFloat = 10
    /// Between a section header ("Parameters", "Returns") and the content it introduces -- tighter than
    /// ``sectionSpacing`` so the header reads as attached to what follows it rather than as its own section.
    package static let headerToContentSpacing: CGFloat = 4
    /// A declaration (or candidate) chip's own inset between its background and the code it backs.
    package static let chipHorizontalPadding: CGFloat = 8
    package static let chipVerticalPadding: CGFloat = 6
    /// The chip's own corner radius, a notch smaller than the panel's own so it reads as set into the glass.
    package static let chipCornerRadius: CGFloat = 4
}

/// The rich hover panel: an arrow-less, non-activating child window styled like Xcode's Quick Help, sized to its
/// content and anchored under the hovered identifier. A `NSVisualEffectView` gives it the system's popover
/// material and corner radius; everything else is a plain `NSStackView` of slots, some of them hidden when the
/// document has nothing for them.
@MainActor
package final class HoverDocPanel {
    /// Whether the panel is currently on screen.
    package private(set) var isVisible = false
    /// Whether the pointer is currently over the panel itself, tracked so the text view's own `mouseExited` can
    /// tell "the pointer left for the panel" from "the pointer left the pane" and not dismiss for the former.
    package private(set) var pointerIsInside = false

    private var panel: NSPanel?
    private weak var attachedWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    private let declarationView = HoverDocPanel.makeCodeTextView()
    /// The declaration's own inset backing, filled with the pane's palette background (see
    /// ``HoverDocument/chipBackground``) rather than left on the panel's vibrancy glass -- a theme's role colors
    /// are chosen to read against the pane they render in, which is not necessarily the same light/dark appearance
    /// as the panel's own popover material. An `NSBox` rather than a raw layer-backed `NSView`: its `fillColor`
    /// and `borderColor` are resolved against the view's effective appearance at every draw, so the chip's own
    /// hairline border and background stay correct across a light/dark appearance change on their own, with no
    /// `viewDidChangeEffectiveAppearance` bookkeeping needed -- a plain `CALayer.borderColor`/`backgroundColor`
    /// bakes in whatever `NSColor` resolved to at the moment it was set, and goes stale otherwise.
    private let declarationChip = HoverDocPanel.makeChip()
    private let bodyTextView = HoverDocPanel.makeProseTextView()
    private let bodyScrollView = NSScrollView()
    private let parametersGrid = NSGridView(numberOfColumns: 2, rows: 0)
    private let parametersHeader = HoverDocPanel.makeSectionLabel("Parameters")
    private let returnsHeader = HoverDocPanel.makeSectionLabel("Returns")
    private let returnsView = HoverDocPanel.makeProseTextView()
    private let diagnosticsStack = NSStackView()
    private let candidatesStack = NSStackView()
    private let contentStack = NSStackView()

    // The text-bearing slots (`declarationView`, `bodyScrollView`, `returnsView`) have no usable intrinsic
    // content size of their own -- an `NSTextView` reports `NSViewNoIntrinsicMetric` for both dimensions, and an
    // `NSScrollView` wrapping one is no different -- so `contentStack` cannot sizeto-fit them from their content the
    // way it can a label or a grid. Without an explicit height constraint they collapse to their initial zero-size
    // frame and the panel renders with the text set but invisible; these are computed and kept up to date every
    // ``render(_:)`` pass.
    private var declarationHeight: NSLayoutConstraint?
    private var bodyHeight: NSLayoutConstraint?
    private var returnsHeight: NSLayoutConstraint?

    package init() {}

    /// Shows (or repositions and re-renders, if already shown) the panel for `document`, anchored at `anchorRect`
    /// (in `textView`'s own coordinates) and attached as a child window of `textView`'s own window, whose
    /// appearance it matches.
    package func show(document: HoverDocument, anchorRect: NSRect, in textView: NSTextView) {
        guard let hostWindow = textView.window, let screen = hostWindow.screen else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.appearance = textView.effectiveAppearance
        let contentHeight = render(document)

        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: contentHeight)
        bodyScrollView.hasVerticalScroller = scrolls
        let size = NSSize(width: HoverPanelSizing.width, height: height)
        panel.setContentSize(size)

        setOrigin(forAnchorRect: anchorRect, panelSize: size, in: textView, hostWindow: hostWindow, screen: screen)

        if !isVisible {
            hostWindow.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
            isVisible = true
        }
        attachedWindow = hostWindow
    }

    /// Repositions an already-visible panel to a freshly recomputed `anchorRect` (in `textView`'s own
    /// coordinates), without re-rendering or resizing it -- what ``DocHoverController`` calls on every scroll to
    /// keep the panel tracking the identifier it documents. A no-op if the panel is not currently showing.
    package func reposition(anchorRect: NSRect, in textView: NSTextView) {
        guard isVisible, let panel, let hostWindow = textView.window, let screen = hostWindow.screen else { return }
        setOrigin(
            forAnchorRect: anchorRect, panelSize: panel.frame.size, in: textView, hostWindow: hostWindow,
            screen: screen)
    }

    /// The shared origin math ``show(document:anchorRect:in:)`` and ``reposition(anchorRect:in:)`` both need:
    /// converts `anchorRect` to screen coordinates and places the panel per ``HoverPanelSizing/origin``.
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

    /// The content stack's own Auto Layout fitting height at the panel's fixed width, after a fresh layout pass --
    /// for tests only, the ground truth ``show(document:anchorRect:in:)`` sizes the window against: any drift
    /// between the two is exactly the "wasted space" a stale hand-tallied height estimate would otherwise leave
    /// at the bottom of the panel. `nil` before the panel has ever been shown once (nothing to measure yet).
    package var laidOutContentHeightForTests: CGFloat? {
        guard let panel else { return nil }
        panel.contentView?.layoutSubtreeIfNeeded()
        return contentStack.fittingSize.height
    }

    /// The window's own current content height -- for tests only, what ``show(document:anchorRect:in:)`` most
    /// recently sized the panel to, compared against ``laidOutContentHeightForTests`` to catch any daylight
    /// between the two.
    package var panelHeightForTests: CGFloat? { panel?.frame.size.height }

    /// Hides the panel and detaches it from its host window; a no-op when it is not showing.
    package func close() {
        guard let panel, isVisible else { return }
        attachedWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
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

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        // `.behindWindow` blending samples what is behind the window directly, bypassing the layer mask above for
        // that sampled material -- the canonical AppKit fix is a `maskImage`: a resizable rounded-rect template
        // whose alpha channel clips the *material itself*, not just the layer's drawn content, so the glass never
        // bleeds square past the panel's rounded corners.
        effectView.maskImage = Self.roundedMaskImage(cornerRadius: 8)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = HoverPanelMetrics.sectionSpacing
        contentStack.edgeInsets = NSEdgeInsets(
            top: HoverPanelMetrics.edgeInset, left: HoverPanelMetrics.edgeInset, bottom: HoverPanelMetrics.edgeInset,
            right: HoverPanelMetrics.edgeInset)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        bodyScrollView.documentView = bodyTextView
        bodyScrollView.drawsBackground = false
        bodyScrollView.hasVerticalScroller = false
        bodyScrollView.borderType = .noBorder
        bodyScrollView.translatesAutoresizingMaskIntoConstraints = false

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
            declarationChip, bodyScrollView, parametersHeader, parametersGrid, returnsHeader, returnsView,
            candidatesStack, diagnosticsStack
        ] {
            contentStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: HoverPanelSizing.width - 24).isActive = true
        }
        // Tighter than the stack's own `sectionSpacing` between every other pair of siblings: a header reads as
        // attached to the content it introduces, not as a section of its own.
        contentStack.setCustomSpacing(HoverPanelMetrics.headerToContentSpacing, after: parametersHeader)
        contentStack.setCustomSpacing(HoverPanelMetrics.headerToContentSpacing, after: returnsHeader)

        declarationHeight = declarationChip.heightAnchor.constraint(equalToConstant: 0)
        declarationHeight?.isActive = true
        bodyHeight = bodyScrollView.heightAnchor.constraint(equalToConstant: 0)
        bodyHeight?.isActive = true
        returnsHeight = returnsView.heightAnchor.constraint(equalToConstant: 0)
        returnsHeight?.isActive = true

        effectView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: effectView.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor)
        ])
        panel.contentView = effectView

        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        effectView.addTrackingArea(area)
        trackingArea = area
        return panel
    }

    // MARK: Rendering

    /// Renders `document` into every slot and sizes their height constraints, returning the content height
    /// ``show(document:anchorRect:in:)`` feeds to ``HoverPanelSizing/clampedHeight(forContentHeight:)`` to decide
    /// the window's own size and whether the body needs to scroll.
    ///
    /// The chrome's own total height -- every slot but the body -- is measured by running a real Auto Layout pass
    /// over `contentStack` with the body's height constraint pinned to zero, rather than hand-tallying each slot's
    /// height and the stack's spacing between them as this used to: that shadow arithmetic drifted from what the
    /// stack view actually laid out to (a fixed per-row guess for the parameters grid that did not match its real
    /// row height, a candidates group double-counted as two of the stack's own top-level slots when its hairline
    /// separator is nested *inside* the candidates stack rather than a sibling of it, ...), and every drift in that
    /// direction only ever overshoots, padding the window out with real, visible empty space at the bottom past
    /// where `contentStack`'s own `bottomAnchor` (pinned `lessThanOrEqualTo`) actually lets it draw. Asking
    /// `contentStack` for its own `fittingSize` instead makes this the single source of truth for both the sizing
    /// decision and the eventual layout, so the two can never disagree.
    private func render(_ document: HoverDocument) -> CGFloat {
        let innerWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        let chipInnerWidth = innerWidth - 2 * HoverPanelMetrics.chipHorizontalPadding

        declarationView.textStorage?.setAttributedString(document.declaration ?? NSAttributedString())
        declarationChip.isHidden = document.declaration == nil
        declarationChip.fillColor = document.chipBackground ?? .clear
        declarationHeight?.constant =
            declarationChip.isHidden
            ? 0
            : Self.measuredHeight(of: declarationView.textStorage!, width: chipInnerWidth)
                + 2 * HoverPanelMetrics.chipVerticalPadding

        let body = NSMutableAttributedString()
        if let summary = document.summary { body.append(summary) }
        if let discussion = document.discussion {
            if body.length > 0 { body.append(NSAttributedString(string: "\n\n")) }
            body.append(discussion)
        }
        renderParameters(document.parameters)
        parametersHeader.isHidden = document.parameters.isEmpty
        parametersGrid.isHidden = document.parameters.isEmpty

        returnsView.textStorage?.setAttributedString(document.returns ?? NSAttributedString())
        returnsHeader.isHidden = document.returns == nil
        returnsView.isHidden = document.returns == nil
        returnsHeight?.constant =
            returnsView.isHidden ? 0 : Self.measuredHeight(of: returnsView.textStorage!, width: innerWidth)

        renderCandidates(document.extraCandidates, chipBackground: document.chipBackground)
        candidatesStack.isHidden = document.extraCandidates.isEmpty

        renderDiagnostics(document.diagnostics)
        diagnosticsStack.isHidden = document.diagnostics.isEmpty

        // A declaration with nothing else to show (no prose from any tier, no parameters, no returns, no other
        // candidates, no diagnostics) is a real, checked answer -- "nobody wrote anything about this" -- not a
        // loading gap or a bug; saying so plainly keeps an otherwise-empty panel from reading as broken.
        if body.length == 0, !declarationChip.isHidden, parametersGrid.isHidden, returnsView.isHidden,
            candidatesStack.isHidden, diagnosticsStack.isHidden
        {
            body.append(Self.noDocumentationPlaceholder)
        }
        bodyTextView.textStorage?.setAttributedString(body)
        bodyScrollView.isHidden = body.length == 0

        let bodyFullHeight =
            bodyScrollView.isHidden ? 0 : Self.measuredHeight(of: bodyTextView.textStorage!, width: innerWidth)
        bodyHeight?.constant = 0
        contentStack.layoutSubtreeIfNeeded()
        let chromeHeight = contentStack.fittingSize.height

        // Budgeted against every other slot's own height, not the panel's full cap outright -- otherwise a long
        // discussion alongside a full declaration/parameters/diagnostics chrome could ask for more height than
        // the clamped window actually has, clipping content the body's own scroller can never reach.
        let budget = HoverPanelSizing.bodyHeightBudget(chromeHeight: chromeHeight)
        bodyHeight?.constant = bodyScrollView.isHidden ? 0 : min(bodyFullHeight, budget)

        return bodyScrollView.isHidden ? chromeHeight : chromeHeight + bodyFullHeight
    }

    private static let noDocumentationPlaceholder = NSAttributedString(
        string: "No documentation",
        attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor
        ]
    )
}

// MARK: - Slot rendering, measurement, and view factories
//
// Pulled out of the class body itself (rather than merely organized within it) so the class's own body stays
// well clear of SwiftLint's `type_body_length`: `private` in Swift already extends to every extension of a type
// in the same file, so nothing here loses access to the class's stored properties.
extension HoverDocPanel {
    fileprivate func renderParameters(_ parameters: [HoverDocument.Field]) {
        while parametersGrid.numberOfRows > 0 {
            parametersGrid.removeRow(at: parametersGrid.numberOfRows - 1)
        }
        for parameter in parameters {
            let nameLabel = NSTextField(labelWithString: parameter.name)
            nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            nameLabel.textColor = .secondaryLabelColor
            let textLabel = NSTextField(labelWithAttributedString: parameter.text)
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.preferredMaxLayoutWidth =
                HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset - 90
            parametersGrid.addRow(with: [nameLabel, textLabel])
        }
    }

    /// Rebuilds the candidates group's rows; each row's own height constraint is set from its real measured
    /// content (a candidate's declaration wraps to however many lines its own text needs), but the group's total
    /// contribution to the panel's own height is never hand-tallied here -- ``render(_:)`` reads it straight back
    /// off `contentStack`'s own Auto Layout fitting size once every row is in place, so it can never drift from
    /// what actually gets drawn.
    fileprivate func renderCandidates(_ candidates: [HoverDocument.Candidate], chipBackground: NSColor?) {
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let innerWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        let chipInnerWidth = innerWidth - 2 * HoverPanelMetrics.chipHorizontalPadding
        // A hairline rule ahead of the first candidate, so overloads/other declarations read as a distinct
        // group rather than floating ambiguously after the main declaration's body.
        if !candidates.isEmpty {
            candidatesStack.addArrangedSubview(HoverDocPanel.makeCandidatesSeparator())
        }
        for candidate in candidates where candidate.declaration != nil || candidate.summary != nil {
            if let declaration = candidate.declaration {
                let view = HoverDocPanel.makeCodeTextView()
                view.textStorage?.setAttributedString(declaration)
                let chip = HoverDocPanel.makeChip()
                Self.configureChip(chip, around: view)
                chip.fillColor = chipBackground ?? .clear
                let rowHeight =
                    Self.measuredHeight(of: view.textStorage!, width: chipInnerWidth)
                    + 2 * HoverPanelMetrics.chipVerticalPadding
                candidatesStack.addArrangedSubview(chip)
                chip.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                chip.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
            // A candidate's own prose (its summary), the same content ``HoverMarkdownStructurer`` parsed for it --
            // dropping it here, as the panel used to, silently threw away real documentation for any doc-comment-
            // index answer that resolved to more than one same-named declaration (a common shape for a small,
            // frequently reused type name declared in several files), even though the tier that answered still
            // resolved it correctly.
            if let summary = candidate.summary {
                let view = HoverDocPanel.makeProseTextView()
                view.textStorage?.setAttributedString(summary)
                let rowHeight = Self.measuredHeight(of: view.textStorage!, width: innerWidth)
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

    fileprivate static func measuredHeight(of storage: NSTextStorage, width: CGFloat) -> CGFloat {
        guard storage.length > 0 else { return 0 }
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(storage)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return layoutManager.usageBoundsForTextContainer.height
    }

    /// A declaration (or candidate) chip: a custom `NSBox`, filled and stroked rather than left flat, so it reads
    /// as a distinct surface set into the panel's own glass. `NSBox`'s `fillColor` and `borderColor` are resolved
    /// against the view's effective appearance at draw time, unlike a `CALayer`'s `backgroundColor`/`borderColor`
    /// (both plain `CGColor`s, which bake in whatever the `NSColor` resolved to the moment they were set) -- the
    /// box needs no `viewDidChangeEffectiveAppearance` bookkeeping to stay correct across a light/dark appearance
    /// change the way the panel's previous layer-backed chip would have.
    fileprivate static func makeChip() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = HoverPanelMetrics.chipCornerRadius
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// Pins `textView` inside `chip`, inset by ``HoverPanelMetrics``' own chip padding on every edge, so the
    /// chip's filled background (set later, in ``render(_:)``, from ``HoverDocument/chipBackground``) reads as an
    /// inset backing behind the code rather than a flush rectangle.
    fileprivate static func configureChip(_ chip: NSBox, around textView: NSTextView) {
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

    fileprivate static func makeCodeTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    fileprivate static func makeProseTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    fileprivate static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

extension HoverDocPanel {
    /// `NSTrackingArea` dispatch by owner selector, the same idiom ``DocHoverController`` itself relies on.
    @objc(mouseEntered:) fileprivate func mouseEntered(with event: NSEvent) { pointerIsInside = true }
    @objc(mouseExited:) fileprivate func mouseExited(with event: NSEvent) { pointerIsInside = false }

    /// A hairline separator sized to the panel's inner width, used ahead of ``renderCandidates(_:)``'s first row.
    fileprivate static func makeCandidatesSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: HoverPanelSizing.width - 24).isActive = true
        return box
    }
}

extension HoverDocPanel {
    /// A resizable, all-black rounded-rect template image sized just past `cornerRadius` on each edge, with cap
    /// insets equal to the radius: stretched over any rect via `NSImageResizingMode.stretch`, its corners keep
    /// their curvature while its edges and center tile flat, the standard shape an `NSVisualEffectView.maskImage`
    /// needs to clip `.behindWindow` material to a rounded rect at any size.
    fileprivate static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
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
