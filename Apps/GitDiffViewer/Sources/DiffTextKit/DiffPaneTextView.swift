package import AppKit
import DiffRendering
import Foundation

/// The text view of both panes, the scrolling pane and a card's: a plain TextKit 2 `NSTextView`, except that copying,
/// dragging or serving a selection as plain text writes the source's characters, bidi controls included, where the
/// text shows the placeholders `BidiControls` puts in their place.
package final class DiffPaneTextView: NSTextView {
    /// The name a text view that is not rich writes its plain text under when no type is asked for.
    private static let legacyString = NSPasteboard.PasteboardType("NSStringPboardType")

    package override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string || type == Self.legacyString, let storage = textStorage else {
            return super.writeSelection(to: pboard, type: type)
        }
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.contains(where: storage.holdsBidiControl(in:)) else {
            return super.writeSelection(to: pboard, type: type)
        }
        // A discontiguous selection writes its ranges in order, a newline apart, as NSTextView does.
        return pboard.setString(ranges.map(storage.sourceText(in:)).joined(separator: "\n"), forType: type)
    }
}

extension NSAttributedString {
    /// Whether `range` holds a placeholder for a bidi control.
    func holdsBidiControl(in range: NSRange) -> Bool {
        var holds = false
        enumerateAttribute(.diffBidiControl, in: range, options: .longestEffectiveRangeNotRequired) { value, _, stop in
            guard value != nil else { return }
            holds = true
            stop.pointee = true
        }
        return holds
    }

    /// The source text of `range`: its characters, with each placeholder for a bidi control turned back into the
    /// control it records.
    func sourceText(in range: NSRange) -> String {
        let text = NSMutableString(string: (string as NSString).substring(with: range))
        enumerateAttribute(.diffBidiControl, in: range, options: .longestEffectiveRangeNotRequired) { value, run, _ in
            guard let control = value as? String else { return }
            // One unit for one: the runs after this one keep their offsets.
            text.replaceCharacters(
                in: NSRange(location: run.location - range.location, length: run.length),
                with: String(repeating: control, count: run.length))
        }
        return text as String
    }
}
