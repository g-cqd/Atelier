package import AppKit
import Foundation
import Synchronization

/// The height a line of a font takes at its natural spacing, measured once per font with TextKit 2 and shared by
/// every palette, pane and backend, so they never disagree on it by a point per row.
///
/// No CoreText formula reproduces TextKit's line height for every font (text-renderer.md §1.3, finding 7), so the
/// height is the frame of a laid-out line fragment rather than a sum of the font's metrics.
package enum FontLineHeight {
    private struct Key: Hashable {
        let name: String
        let size: CGFloat
    }

    private static let measured = Mutex<[Key: CGFloat]>([:])

    /// The height TextKit 2 gives a line of `font`, measured on first use and remembered afterwards.
    /// - Complexity: O(1) once `font` was measured; one single-line layout the first time.
    package static func of(_ font: NSFont) -> CGFloat {
        let key = Key(name: font.fontName, size: font.pointSize)
        if let height = measured.withLock({ $0[key] }) { return height }
        let height = measure(font)
        measured.withLock { $0[key] = height }
        return height
    }

    /// Lays out one line of `font` with TextKit 2 and returns its fragment's height. Callable from any thread: the
    /// text system it builds is its own and does not outlive the call.
    package static func measure(_ font: NSFont) -> CGFloat {
        let storage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 10_000, height: 10_000))
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        storage.addTextLayoutManager(layoutManager)
        storage.textStorage?.setAttributedString(NSAttributedString(string: "X", attributes: [.font: font]))
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var height: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            height = fragment.layoutFragmentFrame.height
            return false
        }
        return height
    }
}
