package import AppKit
import AtelierDiagnostics
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
    /// The overlay diagnostics are read from, and this fragment's row within it; set together, at layout time.
    package var overlay: DiagnosticOverlay?
    package var rowIndex: Int = -1
    /// The band of a gap after this row, at the bottom of the fragment, which stays empty: no row colour reaches it.
    package var bandBelow: CGFloat = 0

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
        drawDiagnostics(at: point, in: context)
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
                context.fill(
                    CGRect(
                        x: point.x + bounds.minX + start, y: point.y + bounds.minY, width: end - start,
                        height: bounds.height))
                context.restoreGState()
            }
        }
    }

    /// Underlines the row's diagnostics beneath its first line fragment, across their column range or the whole
    /// line. Wrapped lines stay bare: `SquiggleRange` columns are relative to the row, not to a wrapped line.
    private func drawDiagnostics(at point: CGPoint, in context: CGContext) {
        guard let overlay, rowIndex >= 0, let row = overlay.row(rowIndex), let line = textLineFragments.first else {
            return
        }
        let bounds = line.typographicBounds
        let y = point.y + bounds.maxY - 2
        guard !row.squiggles.isEmpty else {
            drawSquiggle(
                in: context, color: color(for: row.severity), x0: point.x + bounds.minX,
                x1: point.x + bounds.minX + bounds.width, y: y)
            return
        }
        let length = line.characterRange.length
        for squiggle in row.squiggles where squiggle.start < length {
            let startX = line.locationForCharacter(at: squiggle.start).x
            let endX = line.locationForCharacter(at: min(squiggle.end ?? length, length)).x
            drawSquiggle(
                in: context, color: color(for: squiggle.severity), x0: point.x + bounds.minX + startX,
                x1: point.x + bounds.minX + endX, y: y)
        }
    }

    private func drawSquiggle(in context: CGContext, color: NSColor, x0: CGFloat, x1: CGFloat, y: CGFloat) {
        guard x1 > x0 else { return }
        context.saveGState()
        context.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.2)
        context.setLineDash(phase: 0, lengths: [2, 2])
        context.move(to: CGPoint(x: x0, y: y))
        context.addLine(to: CGPoint(x: x1, y: y))
        context.strokePath()
        context.restoreGState()
    }

    private func color(for severity: Finding.Severity) -> NSColor {
        switch severity {
            case .error: .systemRed
            case .warning: .systemYellow
            case .note: .systemGray
        }
    }

    /// Spans the whole document width (viewport or longest line, whichever is wider) for every line of the
    /// paragraph, including wrapped continuation lines, down to the band of a gap after it. Kept bounded because
    /// oversized fragment surfaces exceed the maximum layer size and then draw nothing at all.
    private func backgroundRect(origin: CGPoint) -> CGRect {
        let width = max(metrics?.width ?? 0, layoutFragmentFrame.width) + 2 * Self.horizontalOverdraw
        return CGRect(
            x: origin.x - layoutFragmentFrame.minX - Self.horizontalOverdraw,
            y: origin.y,
            width: width,
            height: max(layoutFragmentFrame.height - bandBelow, 0)
        )
    }

    private static let horizontalOverdraw: CGFloat = 8
}
