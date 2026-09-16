import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI
import Synchronization

/// Width of the pane's viewport, written on the main thread by the coordinator and read by fragments while drawing,
/// which TextKit may do on its own threads; the atomic makes that cross-thread hand-off explicit.
package final class ViewportMetrics: Sendable {
    private let storage = Atomic<Double>(0)

    package var width: CGFloat {
        get { CGFloat(storage.load(ordering: .relaxed)) }
        set { storage.store(Double(newValue), ordering: .relaxed) }
    }
}

/// Draws a full-width background behind its line before the glyphs, which is how the diff colors whole rows
/// without stretching background attributes to the container edge.
package final class DiffLayoutFragment: NSTextLayoutFragment {
    package var backgroundColor: NSColor?
    package var metrics: ViewportMetrics?
    /// How far to raise the glyphs inside their line, to centre them when the line is taller than they need.
    package var baselineOffset: CGFloat = 0

    package override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(backgroundRect(origin: .zero))
    }

    package override func draw(at point: CGPoint, in context: CGContext) {
        if let backgroundColor {
            context.saveGState()
            context.setFillColor(backgroundColor.cgColor)
            context.fill(backgroundRect(origin: point))
            context.restoreGState()
        }
        drawEmphasis(at: point, in: context)
        guard baselineOffset != 0 else { return super.draw(at: point, in: context) }
        // Only the glyphs move: the backgrounds above fill the line as it was laid out.
        context.saveGState()
        context.translateBy(x: 0, y: -baselineOffset)
        super.draw(at: point, in: context)
        context.restoreGState()
    }

    /// The intraline changes, each filled over the whole height of its line, so they match the row whatever the
    /// line height; a background attribute would stop at the glyphs.
    private func drawEmphasis(at point: CGPoint, in context: CGContext) {
        for line in textLineFragments {
            let bounds = line.typographicBounds
            line.attributedString.enumerateAttribute(.diffEmphasis, in: line.characterRange) { value, range, _ in
                guard let color = value as? NSColor, range.length > 0 else { return }
                let start = line.locationForCharacter(at: range.location).x
                let end = line.locationForCharacter(at: range.location + range.length).x
                guard end > start else { return }
                context.saveGState()
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: point.x + bounds.minX + start, y: point.y + bounds.minY, width: end - start, height: bounds.height))
                context.restoreGState()
            }
        }
    }

    /// Spans the whole document width (viewport or longest line, whichever is wider) for every line of the
    /// paragraph, including wrapped continuation lines. Kept bounded because oversized fragment surfaces exceed the
    /// maximum layer size and then draw nothing at all.
    private func backgroundRect(origin: CGPoint) -> CGRect {
        let width = max(metrics?.width ?? 0, layoutFragmentFrame.width) + 2 * Self.horizontalOverdraw
        return CGRect(
            x: origin.x - layoutFragmentFrame.minX - Self.horizontalOverdraw,
            y: origin.y,
            width: width,
            height: layoutFragmentFrame.height
        )
    }

    private static let horizontalOverdraw: CGFloat = 8
}
