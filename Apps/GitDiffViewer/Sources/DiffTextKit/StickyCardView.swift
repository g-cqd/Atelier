package import AppKit
import QuartzCore
import SwiftUI

/// A card whose header sticks below its scroll view's top bars while the card scrolls past them.
///
/// The card is one rounded, outlined, shadowed shape. Past the pin line its top follows the line with the header,
/// so the body scrolls beneath the header and nothing scrolled up shows above it; the card's bottom then pushes the
/// header out. Sticking reads the enclosing scroll view and moves view origins and layers only: no view changes
/// size while scrolling, so scrolling never lays out or re-evaluates SwiftUI.
package final class StickyCardView: NSView {
    package static let cornerRadius: CGFloat = 10
    /// The weight of the outline and of the hairline under a pinned header.
    package static let lineWidth: CGFloat = 1

    /// The header, at the top of the visible card.
    package let headerView: NSView
    /// The body, below the header, scrolled with the card.
    package let bodyView: NSView
    /// The space kept between the scroll view's top bars and a sticking header.
    package var stickyGap: CGFloat = 16 {
        didSet { if stickyGap != oldValue { needsLayout = true } }
    }
    /// The header's height, measured by the owner; the body fills the rest of the card.
    package var headerHeight: CGFloat = 0 {
        didSet { if headerHeight != oldValue { needsLayout = true } }
    }

    /// The geometry last applied; a scroll that leaves it unchanged costs nothing more.
    private(set) var appliedGeometry: StickyCardGeometry?

    private let shadowView = FlippedView()
    private let shadowLayer = CALayer()
    /// Rounds the card's bottom corners, which stay at the card's bottom.
    private let cardClipView = FlippedView()
    /// Rounds the top corners at the pin line: as tall as the card, and moved rather than resized while sticking.
    private let topClipView = FlippedView()
    /// Cuts the body at the header's bottom, so its text views never see the pointer or draw beneath the header.
    private let bodyClipView = FlippedView()
    private let hairlineView = FlippedView()
    private let outlineView = PassthroughView()
    private let outlineLayer = CALayer()
    private weak var observedClipView: NSClipView?
    private weak var observedSuperview: NSView?

    package init(header: NSView, body: NSView) {
        headerView = header
        bodyView = body
        super.init(frame: .zero)
        wantsLayer = true
        for view in [shadowView, cardClipView, topClipView, bodyClipView, hairlineView, outlineView] {
            view.wantsLayer = true
        }
        // Sublayers AppKit does not manage: it resets a view's own layer shadow from `NSView.shadow`.
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.22
        shadowLayer.shadowRadius = 5
        shadowLayer.shadowOffset = CGSize(width: 0, height: 2)
        shadowView.layer?.addSublayer(shadowLayer)
        outlineLayer.cornerRadius = Self.cornerRadius
        outlineLayer.cornerCurve = .continuous
        outlineLayer.borderWidth = Self.lineWidth
        outlineView.layer?.addSublayer(outlineLayer)
        // Each corner is rounded by exactly one clip; the other clip's edge there is straight.
        Self.clip(cardClipView, toCorners: [.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        Self.clip(topClipView, toCorners: [.layerMinXMinYCorner, .layerMaxXMinYCorner])
        bodyClipView.clipsToBounds = true
        hairlineView.alphaValue = 0
        addSubview(shadowView)
        addSubview(cardClipView)
        addSubview(outlineView)
        cardClipView.addSubview(topClipView)
        topClipView.addSubview(bodyClipView)
        bodyClipView.addSubview(body)
        topClipView.addSubview(header)
        topClipView.addSubview(hairlineView)
        resolveColors()
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    package override var isFlipped: Bool { true }

    /// Whether the hairline under a pinned header shows.
    var isHairlineVisible: Bool { hairlineView.alphaValue > 0 }

    /// The header's frame in this view: where it shows, sticking or not.
    var headerFrame: CGRect { convert(headerView.frame, from: topClipView) }

    package override func layout() {
        super.layout()
        let width = bounds.width
        let bodyHeight = max(bounds.height - headerHeight, 0)
        for view in [shadowView, cardClipView, outlineView] { view.frame = bounds }
        topClipView.setFrameSize(bounds.size)
        headerView.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        bodyClipView.frame = CGRect(x: 0, y: headerHeight, width: width, height: bodyHeight)
        bodyView.setFrameSize(CGSize(width: width, height: bodyHeight))
        // Inset by the outline, which is drawn above it, so the two never overlap.
        hairlineView.frame = CGRect(
            x: Self.lineWidth, y: headerHeight, width: max(width - 2 * Self.lineWidth, 0), height: Self.lineWidth)
        apply(currentGeometry(), after: nil)
    }

    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        followEnclosingScrollView()
    }

    package override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        followEnclosingScrollView()
        followSuperviewFrame()
    }

    package override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    /// Only the visible card takes clicks: the area a pinned header left above it belongs to what lies behind.
    package override func hitTest(_ point: NSPoint) -> NSView? {
        guard (appliedGeometry?.clipFrame ?? bounds).contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    private func followEnclosingScrollView() {
        let clip = window == nil ? nil : enclosingScrollView?.contentView
        guard clip !== observedClipView else { return }
        let center = NotificationCenter.default
        if let observedClipView {
            center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = clip
        if let clip {
            clip.postsBoundsChangedNotifications = true
            center.addObserver(
                self, selector: #selector(placementDidChange(_:)), name: NSView.boundsDidChangeNotification,
                object: clip)
        }
        placementDidChange(nil)
    }

    /// SwiftUI moves a card by moving the view that hosts it, which leaves this view's own frame unchanged.
    private func followSuperviewFrame() {
        guard superview !== observedSuperview else { return }
        let center = NotificationCenter.default
        if let observedSuperview {
            center.removeObserver(self, name: NSView.frameDidChangeNotification, object: observedSuperview)
        }
        observedSuperview = superview
        if let superview {
            superview.postsFrameChangedNotifications = true
            center.addObserver(
                self, selector: #selector(placementDidChange(_:)), name: NSView.frameDidChangeNotification,
                object: superview)
        }
    }

    @objc private func placementDidChange(_ notification: Notification?) {
        let geometry = currentGeometry()
        guard geometry != appliedGeometry else { return }
        apply(geometry, after: appliedGeometry)
    }

    private func currentGeometry() -> StickyCardGeometry {
        StickyCardGeometry(pinY: pinY(), size: bounds.size, headerHeight: headerHeight)
    }

    /// The pin line in this view's coordinates; minus infinity, which keeps the card at rest, outside a scroll view.
    private func pinY() -> CGFloat {
        guard let clip = observedClipView else { return -.infinity }
        let line = StickyCardGeometry.pinY(
            clipBounds: clip.bounds, topInset: clip.contentInsets.top, gap: stickyGap, isFlipped: clip.isFlipped)
        return convert(NSPoint(x: 0, y: line), from: clip).y
    }

    /// Moves the top clip and the body by their origins, and the outline and the shadow by their layers.
    /// - Parameters:
    ///   - geometry: The geometry to show.
    ///   - previous: The geometry on screen, or nil to apply everything.
    private func apply(_ geometry: StickyCardGeometry, after previous: StickyCardGeometry?) {
        let visible = geometry.clipFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topClipView.setFrameOrigin(visible.origin)
        bodyView.setFrameOrigin(geometry.bodyOrigin)
        outlineLayer.frame = visible
        shadowLayer.frame = visible
        if visible.size != previous?.clipFrame.size {
            shadowLayer.shadowPath = Self.outline(of: CGRect(origin: .zero, size: visible.size))
        }
        if geometry.isPinned != previous?.isPinned {
            hairlineView.alphaValue = geometry.isPinned ? 1 : 0
        }
        CATransaction.commit()
        appliedGeometry = geometry
    }

    /// Layer colors are resolved once per appearance: a `CGColor` does not follow appearance changes.
    private func resolveColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let separator = NSColor.separatorColor.cgColor
            outlineLayer.borderColor = separator
            hairlineView.layer?.backgroundColor = separator
        }
    }

    private static func clip(_ view: NSView, toCorners corners: CACornerMask) {
        view.clipsToBounds = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.maskedCorners = corners
    }

    private static func outline(of rect: CGRect) -> CGPath {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous).cgPath
    }
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Draws without taking any clicks.
private final class PassthroughView: FlippedView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
