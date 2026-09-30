package import AppKit
import DiffRendering
import Foundation

/// The text view of both panes, the scrolling pane and a card's: a plain TextKit 2 `NSTextView`, except that copying,
/// dragging or serving a selection as plain text writes the source's characters, bidi controls included, where the
/// text shows the placeholders `BidiControls` puts in their place.
package final class DiffPaneTextView: NSTextView {
    /// The name a text view that is not rich writes its plain text under when no type is asked for.
    private static let legacyString = NSPasteboard.PasteboardType("NSStringPboardType")

    /// Called at the end of each layout pass, once TextKit has laid out what shows.
    package var onLayout: (() -> Void)?
    /// Called when a live resize of the window ends.
    package var onLiveResizeEnd: (() -> Void)?

    /// Whether the text container sits at the container inset exactly, as a card's does, instead of where AppKit
    /// puts it.
    ///
    /// AppKit reads the origin on every pass, to place the viewport and to set up drawing, and works it out from the
    /// text's laid-out size when the container does not follow the view's width, as a wrapped card's does not: each
    /// read lays out the whole text first. A card's container is as wide as its view and starts at the inset, so its
    /// origin needs none of that.
    package var placesContainerAtInset = false {
        didSet { if placesContainerAtInset != oldValue { needsLayout = true } }
    }

    /// Whether the view sizes itself to its text when AppKit asks, as when the clip view around it changes frame.
    /// A card sizes its text view itself, and TextKit lays the whole text out to answer.
    package var sizesToFitText = true

    package override func sizeToFit() {
        guard sizesToFitText else { return }
        super.sizeToFit()
    }

    package override var textContainerOrigin: NSPoint {
        guard placesContainerAtInset else { return super.textContainerOrigin }
        return NSPoint(x: textContainerInset.width, y: textContainerInset.height)
    }

    package override func layout() {
        super.layout()
        onLayout?()
    }

    package override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        onLiveResizeEnd?()
    }

    /// Carries out a folding command (DIFF-03), answering whether it did anything; ``ScopeHoverTracker`` sets it.
    package var onFoldCommand: ((ScopeFoldCommand) -> Bool)?

    /// ⌥⌘←, ⌥⌘→, ⌥⌘⇧← and ⌥⌘⇧→ fold and unfold scopes, as in Xcode; where they find nothing to do, the key goes on as
    /// usual.
    package override func keyDown(with event: NSEvent) {
        if let command = ScopeFoldCommand(event), onFoldCommand?(command) == true { return }
        super.keyDown(with: event)
    }

    /// The items a context menu over a point, in this view's coordinates, starts with, set apart from the text view's
    /// own; none while nil or empty. ``DocHoverController`` sets it while attached (book HOVER-14).
    package var contextMenuItems: (@MainActor (NSPoint) -> [NSMenuItem])?

    package override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard let items = contextMenuItems?(convert(event.locationInWindow, from: nil)), !items.isEmpty else {
            return menu
        }
        // A copy: the text view's menu can be one it shares.
        let result = (menu?.copy() as? NSMenu) ?? NSMenu()
        if result.numberOfItems > 0 { result.insertItem(.separator(), at: 0) }
        for item in items.reversed() { result.insertItem(item, at: 0) }
        return result
    }

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
