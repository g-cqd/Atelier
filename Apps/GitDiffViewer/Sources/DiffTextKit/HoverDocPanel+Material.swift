import AppKit
import DiffRendering

// The panel's background (book HOVER-08): Liquid Glass or the popover material, clipped to the panel's rounded
// corners either way, in a window that is otherwise clear, so no square corner shows past the rounded shape.
extension HoverDocPanel {
    /// A new background of `material` holding `host`, which leaves whichever background held it before.
    static func makeBackground(_ material: HoverPanelMaterial, around host: NSView) -> NSView {
        detach(host)
        switch material {
            case .liquidGlass: return makeGlass(around: host)
            case .popover: return makePopoverMaterial(around: host)
        }
    }

    /// Takes `host` out of its background: a glass view lets go of its content view only when told to.
    private static func detach(_ host: NSView) {
        if let glass = sequence(first: host, next: \.superview).lazy.compactMap({ $0 as? NSGlassEffectView }).first,
            glass.contentView === host
        {
            glass.contentView = nil
        }
        host.removeFromSuperview()
    }

    /// Regular glass, which the HIG gives components with a lot of text, such as popovers: it blurs and adjusts the
    /// luminosity of what is behind it to keep text legible over busy code, where clear glass would need a dimming
    /// layer. No tint, so the system's own adaptations, Reduce Transparency and Increase Contrast, apply as they are.
    private static func makeGlass(around host: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = HoverPanelMetrics.panelCornerRadius
        // The glass pins its content view to its own edges.
        glass.contentView = host
        return glass
    }

    /// The popover material the panel had before Liquid Glass, behind the window's own content.
    private static func makePopoverMaterial(around host: NSView) -> NSVisualEffectView {
        let radius = HoverPanelMetrics.panelCornerRadius
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = radius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        // `.behindWindow` material ignores the layer mask; only a `maskImage` clips it to the rounded corners.
        effectView.maskImage = roundedMaskImage(cornerRadius: radius)
        host.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            host.topAnchor.constraint(equalTo: effectView.topAnchor),
            host.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
        return effectView
    }

    /// A stretchable rounded-rect mask with cap insets of `cornerRadius`, so its corners keep their curve at any size.
    static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
