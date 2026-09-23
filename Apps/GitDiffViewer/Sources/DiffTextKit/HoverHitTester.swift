package import AppKit
import DiffCore
package import DiffRendering
import Foundation

/// Which side of a diff a hover hit falls on: the row's old line number, or its new one.
package enum HoverSide: Sendable, Equatable {
    case old
    case new
}

/// A point over an identifier, resolved to the source position it belongs to.
package struct HoverHit: Sendable, Equatable {
    package let fileIndex: Int
    package let side: HoverSide
    /// Zero-based source line: `(newNumber ?? oldNumber) - 1`.
    package let line: Int
    /// Zero-based UTF-16 column within the row's own text.
    package let utf16Column: Int
    /// The row index in `RenderedText.rows`/`lineStarts`.
    package let row: Int
    /// The hovered identifier run's bounds, in text-view coordinates, as laid out when the hit was made.
    package let anchorRect: NSRect
    /// The identifier's document-absolute UTF-16 range in `RenderedText.attributed`, to re-locate it after a scroll.
    package let identifierRange: NSRange
}

/// Maps a point in text-view coordinates to the identifier hovered there.
package enum HoverHitTester {
    /// `nil` over headers, gaps, padding, whitespace or any character that is not part of an identifier.
    @MainActor
    package static func hit(at point: NSPoint, textView: NSTextView, rendered: RenderedText) -> HoverHit? {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return nil }
        let inset = textView.textContainerInset
        // Text-view coordinates include the container inset; layout fragments are reported without it.
        let containerPoint = NSPoint(x: point.x - inset.width, y: point.y - inset.height)
        layoutManager.ensureLayout(
            for: NSRect(x: containerPoint.x - 1, y: containerPoint.y - 1, width: 2, height: 2))
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) else { return nil }
        let fragmentOrigin = fragment.layoutFragmentFrame.origin
        let fragmentLocalPoint = NSPoint(
            x: containerPoint.x - fragmentOrigin.x, y: containerPoint.y - fragmentOrigin.y)
        guard
            let line = fragment.textLineFragments.first(where: {
                fragmentLocalPoint.y >= $0.typographicBounds.minY && fragmentLocalPoint.y < $0.typographicBounds.maxY
            })
        else { return nil }
        let localIndex = line.characterIndex(for: fragmentLocalPoint)
        let fragmentStart = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        let offset = fragmentStart + localIndex

        let rowIndex = rendered.rowIndex(containing: offset)
        guard offset < rendered.attributed.length, isContentRow(rendered.rows[safe: rowIndex]) else { return nil }
        let meta = rendered.rows[rowIndex]

        let side: HoverSide
        let number: Int
        if let newNumber = meta.newNumber {
            side = .new
            number = newNumber
        } else if let oldNumber = meta.oldNumber {
            side = .old
            number = oldNumber
        } else {
            return nil
        }

        let rowStart = rendered.lineStarts[rowIndex]
        let rowEnd =
            rowIndex + 1 < rendered.lineStarts.count
            ? rendered.lineStarts[rowIndex + 1] - 1 : rendered.attributed.length
        guard offset < rowEnd else { return nil }
        let string = rendered.attributed.string as NSString
        guard let identifierRange = identifierRange(in: string, at: offset, rowStart: rowStart, rowEnd: rowEnd) else {
            return nil
        }

        let anchorRect = Self.rect(
            forIdentifierRange: identifierRange, fragmentOrigin: fragmentOrigin, fragmentStart: fragmentStart,
            line: line, inset: inset)

        return HoverHit(
            fileIndex: meta.fileIndex, side: side, line: number - 1, utf16Column: offset - rowStart, row: rowIndex,
            anchorRect: anchorRect, identifierRange: identifierRange)
    }

    /// The current bounds of `identifierRange`, laid out and measured the way ``hit(at:textView:rendered:)``
    /// measures a fresh hit; nil when the range no longer resolves or no layout fragment covers it.
    @MainActor
    package static func anchorRect(for identifierRange: NSRange, textView: NSTextView) -> NSRect? {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let start = contentManager.location(
                layoutManager.documentRange.location, offsetBy: identifierRange.location),
            let end = contentManager.location(start, offsetBy: identifierRange.length),
            let range = NSTextRange(location: start, end: end)
        else { return nil }
        layoutManager.ensureLayout(for: range)
        guard let fragment = layoutManager.textLayoutFragment(for: start) else { return nil }
        let fragmentOrigin = fragment.layoutFragmentFrame.origin
        let fragmentStart = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        guard
            let line = fragment.textLineFragments.first(where: { lineFragment in
                let lineStart = fragmentStart + lineFragment.characterRange.location
                let lineEnd = lineStart + lineFragment.characterRange.length
                return identifierRange.location >= lineStart && identifierRange.location < lineEnd
            })
        else { return nil }
        return Self.rect(
            forIdentifierRange: identifierRange, fragmentOrigin: fragmentOrigin, fragmentStart: fragmentStart,
            line: line, inset: textView.textContainerInset)
    }

    /// `identifierRange`'s bounds within `line`, in text-view coordinates.
    private static func rect(
        forIdentifierRange identifierRange: NSRange, fragmentOrigin: NSPoint, fragmentStart: Int,
        line: NSTextLineFragment, inset: NSSize
    ) -> NSRect {
        let startLocal = identifierRange.location - fragmentStart
        let endLocal = identifierRange.location + identifierRange.length - fragmentStart
        let startPoint = line.locationForCharacter(at: startLocal)
        let endPoint = line.locationForCharacter(at: endLocal)
        let minX = min(startPoint.x, endPoint.x)
        let maxX = max(startPoint.x, endPoint.x)
        return NSRect(
            x: fragmentOrigin.x + minX + inset.width, y: fragmentOrigin.y + line.typographicBounds.minY + inset.height,
            width: maxX - minX, height: line.typographicBounds.height)
    }

    /// Content rows carry source text; gaps, headers and filler rows never do.
    private static func isContentRow(_ meta: RowMeta?) -> Bool {
        guard let meta else { return false }
        switch meta.kind {
            case .context, .added, .removed, .modified: return true
            case .filler, .gap, .header: return false
        }
    }

    /// Whether a UTF-16 unit belongs to an identifier: letters, digits, underscore, or the leading sigil of an
    /// interpolation/escape (`$`, `` ` ``).
    private static func isWordUnit(_ unit: unichar) -> Bool {
        switch unit {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x5F: true  // 0-9, A-Z, a-z, _
            default: unit > 0x7F  // treat non-ASCII (e.g. emoji, accented letters) as part of a token
        }
    }

    private static func isSigil(_ unit: unichar) -> Bool {
        unit == 0x24 || unit == 0x60  // $ or `
    }

    /// The identifier run around `offset`, clamped to `[rowStart, rowEnd)`; `nil` if `offset` is not itself a
    /// word character.
    private static func identifierRange(in string: NSString, at offset: Int, rowStart: Int, rowEnd: Int) -> NSRange? {
        guard offset >= rowStart, offset < rowEnd, isWordUnit(string.character(at: offset)) else { return nil }
        var start = offset
        while start > rowStart, isWordUnit(string.character(at: start - 1)) { start -= 1 }
        var end = offset + 1
        while end < rowEnd, isWordUnit(string.character(at: end)) { end += 1 }
        if start > rowStart, isSigil(string.character(at: start - 1)) { start -= 1 }
        return NSRange(location: start, length: end - start)
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
