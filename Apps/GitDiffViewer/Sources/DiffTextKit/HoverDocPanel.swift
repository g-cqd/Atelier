package import AppKit
package import DiffRendering
import Foundation

/// The panel's fixed sizing rules, pulled out of ``HoverDocPanel`` itself so they are testable without an actual
/// window: a fixed width, a height clamped between a floor and a ceiling (past which only the body scrolls), and
/// where the panel opens relative to the hovered identifier, flipping above it when it would otherwise run off the
/// bottom of the screen.
package enum HoverPanelSizing {
    package static let width: CGFloat = 440
    package static let minHeight: CGFloat = 260
    package static let maxHeight: CGFloat = 420

    /// The panel's own height for `contentHeight` of measured content, and whether the body needs its own inner
    /// scroll to show the rest: the chrome around it (header, declaration, parameters, footer) is always shown in
    /// full, only the body's prose ever scrolls.
    package static func clampedHeight(forContentHeight contentHeight: CGFloat) -> (height: CGFloat, scrolls: Bool) {
        guard contentHeight > maxHeight else { return (max(contentHeight, minHeight), false) }
        return (maxHeight, true)
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
    private let bodyTextView = HoverDocPanel.makeProseTextView()
    private let bodyScrollView = NSScrollView()
    private let parametersGrid = NSGridView(numberOfColumns: 2, rows: 0)
    private let parametersHeader = HoverDocPanel.makeSectionLabel("Parameters")
    private let returnsHeader = HoverDocPanel.makeSectionLabel("Returns")
    private let returnsView = HoverDocPanel.makeProseTextView()
    private let diagnosticsStack = NSStackView()
    private let candidatesStack = NSStackView()
    private let footerLabel = HoverDocPanel.makeFooterLabel()
    private let contentStack = NSStackView()

    // The text-bearing slots (`declarationView`, `bodyScrollView`, `returnsView`) have no usable intrinsic
    // content size of their own -- an `NSTextView` reports `NSViewNoIntrinsicMetric` for both dimensions, and an
    // `NSScrollView` wrapping one is no different -- so `contentStack` cannot sizeto-fit them from their content the
    // way it can a label or a grid. Without an explicit height constraint they collapse to their initial zero-size
    // frame and the panel renders with the text set but invisible; these are computed and kept up to date every
    // ``render(_:)`` pass from the same measurement `measuredContentHeight()` already uses.
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
        render(document)

        let contentHeight = measuredContentHeight()
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
        contentStack.spacing = 8
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
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

        for view in [
            declarationView, bodyScrollView, parametersHeader, parametersGrid, returnsHeader, returnsView,
            candidatesStack, diagnosticsStack, footerLabel
        ] {
            contentStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: HoverPanelSizing.width - 24).isActive = true
        }

        declarationHeight = declarationView.heightAnchor.constraint(equalToConstant: 0)
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

    private func render(_ document: HoverDocument) {
        let innerWidth = HoverPanelSizing.width - 24

        declarationView.textStorage?.setAttributedString(document.declaration ?? NSAttributedString())
        declarationView.isHidden = document.declaration == nil
        declarationHeight?.constant =
            declarationView.isHidden ? 0 : Self.measuredHeight(of: declarationView.textStorage!, width: innerWidth)

        let body = NSMutableAttributedString()
        if let summary = document.summary { body.append(summary) }
        if let discussion = document.discussion {
            if body.length > 0 { body.append(NSAttributedString(string: "\n\n")) }
            body.append(discussion)
        }
        bodyTextView.textStorage?.setAttributedString(body)
        bodyScrollView.isHidden = body.length == 0
        bodyHeight?.constant =
            bodyScrollView.isHidden
            ? 0 : min(Self.measuredHeight(of: bodyTextView.textStorage!, width: innerWidth), HoverPanelSizing.maxHeight)

        renderParameters(document.parameters)
        parametersHeader.isHidden = document.parameters.isEmpty
        parametersGrid.isHidden = document.parameters.isEmpty

        returnsView.textStorage?.setAttributedString(document.returns ?? NSAttributedString())
        returnsHeader.isHidden = document.returns == nil
        returnsView.isHidden = document.returns == nil
        returnsHeight?.constant =
            returnsView.isHidden ? 0 : Self.measuredHeight(of: returnsView.textStorage!, width: innerWidth)

        renderCandidates(document.extraCandidates)
        candidatesStack.isHidden = document.extraCandidates.isEmpty

        renderDiagnostics(document.diagnostics)
        diagnosticsStack.isHidden = document.diagnostics.isEmpty

        footerLabel.stringValue = document.provenance.label
        footerLabel.isHidden = document.provenance.label.isEmpty
    }

    private func renderParameters(_ parameters: [HoverDocument.Field]) {
        while parametersGrid.numberOfRows > 0 {
            parametersGrid.removeRow(at: parametersGrid.numberOfRows - 1)
        }
        for parameter in parameters {
            let nameLabel = NSTextField(labelWithString: parameter.name)
            nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            nameLabel.textColor = .secondaryLabelColor
            let textLabel = NSTextField(labelWithAttributedString: parameter.text)
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.preferredMaxLayoutWidth = HoverPanelSizing.width - 24 - 90
            parametersGrid.addRow(with: [nameLabel, textLabel])
        }
    }

    private func renderCandidates(_ candidates: [HoverDocument.Candidate]) {
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let innerWidth = HoverPanelSizing.width - 24
        for candidate in candidates {
            guard let declaration = candidate.declaration else { continue }
            let view = HoverDocPanel.makeCodeTextView()
            view.textStorage?.setAttributedString(declaration)
            candidatesStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
            view.heightAnchor
                .constraint(
                    equalToConstant: Self.measuredHeight(of: view.textStorage!, width: innerWidth)
                )
                .isActive = true
        }
    }

    private func renderDiagnostics(_ diagnostics: [HoverDocument.DiagnosticEntry]) {
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

    /// The total height the content stack's slots ask for at the panel's fixed width, measuring the two rich-text
    /// slots (the body and the declaration) with `NSTextLayoutManager` directly since they have not been laid out
    /// in a window yet.
    private func measuredContentHeight() -> CGFloat {
        let innerWidth = HoverPanelSizing.width - 24
        var total: CGFloat = contentStack.edgeInsets.top + contentStack.edgeInsets.bottom
        var visibleSlots = 0
        if let declaration = declarationView.textStorage, !declarationView.isHidden {
            total += Self.measuredHeight(of: declaration, width: innerWidth)
            visibleSlots += 1
        }
        if let body = bodyTextView.textStorage, !bodyScrollView.isHidden {
            total += min(Self.measuredHeight(of: body, width: innerWidth), HoverPanelSizing.maxHeight)
            visibleSlots += 1
        }
        if !parametersGrid.isHidden {
            total += CGFloat(parametersGrid.numberOfRows) * 20
            visibleSlots += 1
        }
        if !returnsView.isHidden, let returns = returnsView.textStorage {
            total += Self.measuredHeight(of: returns, width: innerWidth)
            visibleSlots += 1
        }
        if !candidatesStack.isHidden {
            total += CGFloat(candidatesStack.arrangedSubviews.count) * 24
            visibleSlots += 1
        }
        if !diagnosticsStack.isHidden {
            total += CGFloat(diagnosticsStack.arrangedSubviews.count) * 20
            visibleSlots += 1
        }
        if !footerLabel.isHidden {
            total += 16
            visibleSlots += 1
        }
        total += CGFloat(max(visibleSlots - 1, 0)) * contentStack.spacing
        return total
    }

    private static func measuredHeight(of storage: NSTextStorage, width: CGFloat) -> CGFloat {
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

    private static func makeCodeTextView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private static func makeProseTextView() -> NSTextView {
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

    private static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private static func makeFooterLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10, weight: .regular)
        label.textColor = .tertiaryLabelColor
        return label
    }
}

extension HoverDocPanel {
    /// `NSTrackingArea` dispatch by owner selector, the same idiom ``DocHoverController`` itself relies on.
    @objc(mouseEntered:) fileprivate func mouseEntered(with event: NSEvent) { pointerIsInside = true }
    @objc(mouseExited:) fileprivate func mouseExited(with event: NSEvent) { pointerIsInside = false }
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
