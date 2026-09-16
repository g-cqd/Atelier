import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

/// Overview strip of one pane: every row is a bar whose length follows the line and whose color follows the change
/// kind, with the rows currently on screen framed. The bars are rasterized once per document and size.
package final class MinimapView: NSView {
    package static let width: CGFloat = 64

    package var rendered: RenderedText? {
        didSet {
            bars = nil
            needsDisplay = true
        }
    }

    /// Rows currently visible in the pane, asked for at draw time.
    package var visibleRows: () -> Range<Int> = { 0..<0 }
    /// Called with the row under the pointer while clicking or dragging.
    package var onSelectRow: (Int) -> Void = { _ in }

    /// The pane this strip belongs to; wheel events over the strip scroll it.
    package weak var scrollView: NSScrollView?

    private var bars: (size: CGSize, image: CGImage)?
    private let horizontalPadding: CGFloat = 4
    private let longestBar = 100

    package override var isFlipped: Bool { true }

    package override func draw(_ dirtyRect: NSRect) {
        (rendered?.palette ?? .system).gutterBackground.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()

        guard let rendered, !rendered.rows.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        if bars?.size != bounds.size {
            bars = rasterizeBars(rendered: rendered).map { (bounds.size, $0) }
        }
        if let image = bars?.image {
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: bounds.size))
            context.restoreGState()
        }

        let geometry = MinimapGeometry(rowCount: rendered.rows.count, height: bounds.height)
        let visible = visibleRows()
        guard !visible.isEmpty else { return }
        let top = geometry.y(ofRow: visible.lowerBound)
        let bottom = max(geometry.y(ofRow: visible.upperBound), top + 2)
        let viewport = NSRect(x: 1, y: top, width: bounds.width - 1, height: bottom - top)
        rendered.palette.textColor.withAlphaComponent(0.12).setFill()
        viewport.fill()
        rendered.palette.textColor.withAlphaComponent(0.3).setStroke()
        NSBezierPath(rect: viewport.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    @objc package func setNeedsDisplayOnScroll(_ notification: Notification) {
        needsDisplay = true
    }

    package override func scrollWheel(with event: NSEvent) {
        scrollView?.scrollWheel(with: event)
    }

    package override func mouseDown(with event: NSEvent) {
        select(at: event)
    }

    package override func mouseDragged(with event: NSEvent) {
        select(at: event)
    }

    private func select(at event: NSEvent) {
        guard let rendered, !rendered.rows.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        onSelectRow(MinimapGeometry(rowCount: rendered.rows.count, height: bounds.height).row(atY: point.y))
    }

    /// Draws the bars into a bitmap at the backing scale; the bitmap is flipped back when drawn.
    ///
    /// Detail follows the density: one bar per row, then one bar per point summarizing its rows by strongest change
    /// kind and longest line, then a schematic map where context is a faint constant bar and only changes stand out.
    private func rasterizeBars(rendered: RenderedText) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)

        let geometry = MinimapGeometry(rowCount: rendered.rows.count, height: bounds.height)
        let barSpace = bounds.width - 2 * horizontalPadding
        for bucket in buckets(of: rendered, geometry: geometry) {
            guard let color = rendered.palette.minimapColor(for: bucket.kind, side: rendered.side) else { continue }
            let share: CGFloat = switch geometry.detail {
            case .full, .aggregated: CGFloat(min(bucket.length, longestBar)) / CGFloat(longestBar)
            case .schematic: bucket.kind == .context ? 0.35 : 1
            }
            let barHeight = max(bucket.height * 0.8, 1)
            context.setFillColor(color.cgColor)
            context.fill(CGRect(
                x: horizontalPadding,
                y: bounds.height - bucket.y - barHeight,
                width: 2 + barSpace * share,
                height: barHeight
            ))
        }
        return context.makeImage()
    }

    private struct Bucket {
        var y: CGFloat
        var height: CGFloat
        var kind: RowKind
        var length: Int
    }

    /// One bucket per row at full detail, otherwise one per point holding the strongest kind and longest line.
    private func buckets(of rendered: RenderedText, geometry: MinimapGeometry) -> [Bucket] {
        func length(ofRow row: Int) -> Int {
            let nextStart = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] : rendered.lineStarts[row] + 1
            return nextStart - rendered.lineStarts[row] - 1
        }
        if geometry.detail == .full {
            return rendered.rows.enumerated().map { row, meta in
                Bucket(y: geometry.y(ofRow: row), height: geometry.pitch, kind: meta.kind, length: length(ofRow: row))
            }
        }
        var buckets = [Bucket?](repeating: nil, count: geometry.bucketCount)
        for (row, meta) in rendered.rows.enumerated() {
            let index = geometry.bucket(ofRow: row)
            let rowLength = length(ofRow: row)
            if var bucket = buckets[index] {
                if Self.priority(of: meta.kind) > Self.priority(of: bucket.kind) { bucket.kind = meta.kind }
                bucket.length = max(bucket.length, rowLength)
                buckets[index] = bucket
            } else {
                buckets[index] = Bucket(y: CGFloat(index), height: 1, kind: meta.kind, length: rowLength)
            }
        }
        return buckets.compactMap { $0 }
    }

    private static func priority(of kind: RowKind) -> Int {
        switch kind {
        case .filler, .gap: 0
        case .context: 1
        case .header: 2
        case .modified: 3
        case .added, .removed: 4
        }
    }
}
