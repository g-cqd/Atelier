import AemiCore
package import AppKit
import DiffRendering
import Foundation

// The context menu's documentation items; apart from the type's file, to keep it within the limits SwiftLint sets.
extension DocHoverController {
    // MARK: Context menu

    /// The items a context menu over `point`, in the attached text view's coordinates, starts with (book HOVER-14):
    /// Show Documentation over an identifier while hover is on, which opens its hover panel at once, and Show Issue
    /// over the underlined range of a finding, which opens the findings under `point` in the popover a click on the
    /// row's line number opens.
    package func contextMenuItems(at point: NSPoint) -> [NSMenuItem] {
        guard let textView, let rendered = renderedProvider?() else { return [] }
        var items: [NSMenuItem] = []
        if isEnabled, let resolve, let hit = HoverHitTester.hit(at: point, textView: textView, rendered: rendered) {
            items.append(
                menuItem("Show Documentation") { [weak self] in self?.lookUp(hit, with: resolve, after: nil) }
            )
        }
        if let gutter = paneGutter,
            let position = HoverHitTester.position(at: point, textView: textView, rendered: rendered),
            let findings = gutter.overlay?.row(position.row)?.findings(underColumn: position.utf16Column),
            !findings.isEmpty
        {
            items.append(
                menuItem("Show Issue") { [weak gutter] in gutter?.showFindings(findings, ofRow: position.row) }
            )
        }
        return items
    }

    /// The gutter of the pane the text view shows in, which holds the pane's findings and opens them.
    var paneGutter: DiffGutterView? {
        guard let textView else { return nil }
        return sequence(first: textView as NSView, next: \.superview).lazy.compactMap { $0 as? DiffPaneView }.first?
            .gutterView
    }

    /// A menu item that runs `action` when chosen.
    func menuItem(_ title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MenuAction(action)
        return item
    }

    @objc func performMenuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
    }
}
