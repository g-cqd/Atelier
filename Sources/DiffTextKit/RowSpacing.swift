package import AppKit
import DiffCore
package import DiffRendering
import Foundation
import SwiftUI

/// Row measurement and paragraph spacing over a TextKit 2 text system, shared by the scrolling split panes and
/// the detached card layouts so both align rows the same way.
@MainActor
package enum RowSpacing {
    /// Height of each row's wrapped lines, excluding any paragraph spacing a previous alignment applied.
    package static func rowHeights(in layoutManager: NSTextLayoutManager) -> [Double] {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var heights: [Double] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            heights.append(fragment.textLineFragments.reduce(0) { $0 + $1.typographicBounds.height })
            return true
        }
        return heights
    }

    /// Sets the paragraph spacing of every row to `spacing[row]` (or zero past the end), touching only rows that
    /// change. Returns whether any row changed.
    @discardableResult
    package static func apply(_ spacing: [Double], to contentStorage: NSTextContentStorage, rendered: RenderedText) -> Bool {
        guard let storage = contentStorage.textStorage else { return false }
        let length = storage.length
        var changed = false
        contentStorage.performEditingTransaction {
            storage.beginEditing()
            for (row, start) in rendered.lineStarts.enumerated() {
                let end = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] : length
                guard end > start, let current = storage.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle else { continue }
                let target = row < spacing.count ? spacing[row] : 0
                guard current.paragraphSpacing != target, let style = current.mutableCopy() as? NSMutableParagraphStyle else { continue }
                style.paragraphSpacing = target
                storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: end - start))
                changed = true
            }
            storage.endEditing()
        }
        return changed
    }
}
