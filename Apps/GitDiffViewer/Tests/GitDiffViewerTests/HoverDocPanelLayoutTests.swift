import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The panel's constraints hold together for every shape of document: none is broken to recover from a conflict, and
/// none leaves a view's frame undetermined.
@MainActor
struct HoverDocPanelLayoutTests {
    private static func code(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
    }

    private static func prose(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }

    /// Documents with and without a declaration, and with and without parameters, in an order that shows every slot
    /// after it was hidden, and hides every slot after it was shown.
    private static let shapes: [(name: String, document: HoverDocument)] = [
        ("a declaration alone", HoverDocument(declaration: code("struct CameraConfiguration"))),
        ("a summary without a declaration", HoverDocument(summary: prose("Configures a capture session."))),
        (
            "a declaration with parameters",
            HoverDocument(
                title: "configure(session:)", declaration: code("func configure(session: CaptureSession) -> Bool"),
                summary: prose("Configures a capture session."),
                parameters: [HoverDocument.Field(name: "session", text: prose("The session to configure."))],
                returns: prose("Whether it succeeded."))
        ),
        (
            "parameters without a declaration",
            HoverDocument(
                summary: prose("Configures a capture session."),
                parameters: [HoverDocument.Field(name: "session", text: prose("The session to configure."))])
        ),
        ("a declaration alone, again", HoverDocument(declaration: code("struct CameraConfiguration")))
    ]

    /// The value of `attribute` for `frame`, in a space whose y grows downward, as a constraint reads it.
    private static func value(of attribute: NSLayoutConstraint.Attribute, in frame: NSRect, flipped: Bool) -> CGFloat? {
        let top = flipped ? frame.minY : -frame.maxY
        switch attribute {
            case .left, .leading: return frame.minX
            case .right, .trailing: return frame.maxX
            case .centerX: return frame.midX
            case .width: return frame.width
            case .top: return top
            case .bottom: return top + frame.height
            case .centerY: return top + frame.height / 2
            case .height: return frame.height
            default: return nil
        }
    }

    /// The required constraints among `root`'s views that the views' laid-out alignment rectangles break, described.
    ///
    /// A constraint on an item other than a view in `root`, or on an attribute other than an edge, a center or a size,
    /// is not checked, and neither is a view's content size, which hugs and resists below the required priority.
    private static func brokenConstraints(under root: NSView, views: [NSView]) -> [String] {
        func frame(of item: AnyObject?) -> NSRect? {
            guard let view = item as? NSView, view === root || view.isDescendant(of: root),
                let superview = view.superview
            else { return nil }
            return superview.convert(view.alignmentRect(forFrame: view.frame), to: root)
        }
        var broken: [String] = []
        let checked = views.flatMap(\.constraints)
            .filter {
                $0.isActive && $0.priority == .required
                    && String(describing: type(of: $0)) != "NSContentSizeLayoutConstraint"
            }
        for constraint in checked {
            guard let firstFrame = frame(of: constraint.firstItem),
                let first = value(of: constraint.firstAttribute, in: firstFrame, flipped: root.isFlipped)
            else { continue }
            var second: CGFloat = 0
            if constraint.secondAttribute != .notAnAttribute {
                guard let secondFrame = frame(of: constraint.secondItem),
                    let value = value(of: constraint.secondAttribute, in: secondFrame, flipped: root.isFlipped)
                else { continue }
                second = value
            }
            let target = second * constraint.multiplier + constraint.constant
            let holds =
                switch constraint.relation {
                    case .equal: abs(first - target) < 0.5
                    case .lessThanOrEqual: first <= target + 0.5
                    case .greaterThanOrEqual: first >= target - 0.5
                    @unknown default: true
                }
            if !holds {
                broken.append("\(constraint) (first \(first), target \(target))")
            }
        }
        return broken
    }

    @Test(arguments: HoverPanelMaterial.allCases)
    func `every document shape lays the panel out with no conflict and no ambiguity`(
        material: HoverPanelMaterial
    ) throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        let appearance = try #require(NSAppearance(named: .aqua))

        for (name, document) in Self.shapes {
            panel.prepareOffscreenForTests(document: document, material: material, appearance: appearance)
            let root = try #require(panel.contentViewForTests)
            root.layoutSubtreeIfNeeded()
            var views: [NSView] = []
            var pending = [root]
            while let view = pending.popLast() {
                views.append(view)
                // TextKit's own views inside a text view are its business, and are placed by the text view.
                if !(view is NSTextView) { pending.append(contentsOf: view.subviews) }
            }
            // A hidden slot is detached from the stack, which no longer places it: only the shown views must be
            // placed, and only by constraints where they opt into them.
            let ambiguous = views.filter {
                !$0.isHiddenOrHasHiddenAncestor && !$0.translatesAutoresizingMaskIntoConstraints
                    && $0.hasAmbiguousLayout
            }
            let broken = Self.brokenConstraints(under: root, views: views)

            #expect(ambiguous.isEmpty, "\(name): ambiguous \(ambiguous)")
            #expect(broken.isEmpty, "\(name): broken \(broken)")
        }
    }
}
