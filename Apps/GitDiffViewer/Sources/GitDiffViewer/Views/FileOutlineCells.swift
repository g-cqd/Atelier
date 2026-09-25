import AppKit
import AtelierFileTree
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The heading of a section; the outline view gives group rows their look, this only provides the text field.
final class SectionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SectionCellView")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Icon, name and the change badge at the trailing edge, the same badge as the file cards. The standard outlets
/// let the source-list style size the font and the icon after the system sidebar setting.
final class FileCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FileCellView")

    private let badge = ChangeBadgeView()

    /// The row's selection look, forwarded to the badge by hand: NSTableCellView passes it on to its text field and
    /// image view only, so without this the badge never learns it sits on a focused selection.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { badge.backgroundStyle = backgroundStyle }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyDown
        image.setContentHuggingPriority(.required, for: .horizontal)
        image.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.cell?.truncatesLastVisibleLine = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [image, text, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = image
        textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
            badge.widthAnchor.constraint(equalToConstant: ChangeGlyph.size),
            badge.heightAnchor.constraint(equalToConstant: ChangeGlyph.size),
            // As far from the row's edge as from its top and bottom, so the badge sits square in its corner.
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(24 - ChangeGlyph.size) / 2),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(
        node: PathNode, glyph: ChangeGlyph?, scheme: BadgeScheme, state: BadgeChangeState, detail: String? = nil
    ) {
        imageView?.image = NSImage(
            systemSymbolName: node.isDirectory ? "folder" : "doc.text",
            accessibilityDescription: node.isDirectory ? "Folder" : "File")
        textField?.stringValue = node.name
        badge.glyph = glyph
        badge.isDimmed = node.isDirectory
        badge.scheme = scheme
        badge.state = state
        let help = [glyph?.title, detail].compactMap(\.self).joined(separator: "\n")
        toolTip = help.isEmpty ? nil : help
        setAccessibilityHelp(toolTip)
    }
}

/// A commit section's header: its subject, tail-truncated, and the number of files it lists, trailing in secondary
/// text; everything else about the commit is in the tooltip, which the accessibility label reads too (GIT-06).
final class CommitSectionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("CommitSectionCellView")

    private let count = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let title = NSTextField(labelWithString: "")
        title.lineBreakMode = .byTruncatingTail
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize(for: .small))
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.textColor = .secondaryLabelColor
        count.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [title, count] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            count.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(title: String, count files: Int, tooltip: String?) {
        textField?.stringValue = title
        count.stringValue = files > 0 ? "\(files)" : ""
        toolTip = tooltip
        setAccessibilityLabel(
            [title, files == 1 ? "1 file" : "\(files) files", tooltip].compactMap(\.self).joined(separator: ", "))
    }
}

/// An inert line under a section, in secondary text: why it lists no file, or how many older commits it stands for.
final class NoteCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("NoteCellView")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.textColor = .secondaryLabelColor
        text.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// The target of a menu item that runs a closure, for menus built from values rather than from a responder's
/// selectors. The item holds it as its represented object, since a menu item's target is weak.
final class MenuAction: NSObject {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    @objc func run() {
        perform()
    }

    /// An item titled `title` that runs `perform`, or a disabled one.
    static func item(_ title: String, isEnabled: Bool, _ perform: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(perform)
        let item = NSMenuItem(title: title, action: isEnabled ? #selector(run) : nil, keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }
}
