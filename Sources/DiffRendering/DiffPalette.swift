import AppKit
import DiffCore
import DiffGit
import Foundation

package enum RenderedSide: Sendable, Hashable {
    case unified
    case old
    case new
}

/// Colors and font of the diff panes: the system look, or one derived from an Xcode theme.
package struct DiffPalette: @unchecked Sendable {
    package let font: NSFont
    package let textColor: NSColor
    package let background: NSColor
    package let selection: NSColor
    package let gutterBackground: NSColor
    package let gutterText: NSColor
    package let gutterChangedText: NSColor
    /// Line height as a multiple of the font's, from the theme; 1 for the system palette.
    package let lineHeightMultiple: Double
    /// The height TextKit gives a line of `font` at its natural spacing, measured once here: it is what a line
    /// height multiple multiplies, and rendering runs on several threads at once.
    package let defaultLineHeight: CGFloat
    private let tokenColors: [TokenKind: NSColor]

    package static let system = DiffPalette(
        font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        textColor: .labelColor,
        background: .textBackgroundColor,
        selection: .selectedTextBackgroundColor,
        gutterBackground: .windowBackgroundColor,
        gutterText: .tertiaryLabelColor,
        gutterChangedText: .labelColor,
        lineHeightMultiple: 1,
        tokenColors: [
            .keyword: .systemPink, .string: .systemRed, .comment: .secondaryLabelColor, .number: .systemBlue,
            .type: .systemTeal, .attribute: .systemOrange, .tag: .systemBlue, .attributeName: .systemPurple,
            .entity: .systemOrange,
        ]
    )

    private init(
        font: NSFont, textColor: NSColor, background: NSColor, selection: NSColor, gutterBackground: NSColor,
        gutterText: NSColor, gutterChangedText: NSColor, lineHeightMultiple: Double, tokenColors: [TokenKind: NSColor]
    ) {
        self.font = font
        self.textColor = textColor
        self.background = background
        self.selection = selection
        self.gutterBackground = gutterBackground
        self.gutterText = gutterText
        self.gutterChangedText = gutterChangedText
        self.lineHeightMultiple = lineHeightMultiple
        defaultLineHeight = NSLayoutManager().defaultLineHeight(for: font)
        self.tokenColors = tokenColors
    }

    /// Maps Xcode's syntax categories onto the viewer's token kinds; missing keys fall back to the plain text color.
    package init(theme: XcodeTheme) {
        let text = theme.color(for: "xcode.syntax.plain") ?? Self.system.textColor
        let background = theme.background ?? Self.system.background
        func color(_ keys: String...) -> NSColor {
            keys.lazy.compactMap(theme.color(for:)).first ?? text
        }
        self.init(
            font: theme.plainFont ?? Self.system.font,
            textColor: text,
            background: background,
            selection: theme.selection ?? text.withAlphaComponent(0.2),
            gutterBackground: background.blended(withFraction: 0.04, of: text) ?? background,
            gutterText: text.withAlphaComponent(0.4),
            gutterChangedText: text,
            lineHeightMultiple: theme.lineHeightMultiple ?? 1,
            tokenColors: [
                .keyword: color("xcode.syntax.keyword"),
                .string: color("xcode.syntax.string"),
                .comment: color("xcode.syntax.comment"),
                .number: color("xcode.syntax.number"),
                .type: color("xcode.syntax.identifier.type", "xcode.syntax.identifier.class"),
                .attribute: color("xcode.syntax.attribute"),
                .tag: color("xcode.syntax.keyword"),
                .attributeName: color("xcode.syntax.identifier.variable", "xcode.syntax.attribute"),
                .entity: color("xcode.syntax.number"),
            ]
        )
    }

    package func color(for token: TokenKind) -> NSColor {
        tokenColors[token] ?? textColor
    }

    package func rowBackground(for kind: RowKind, side: RenderedSide, isMoved: Bool = false) -> NSColor? {
        if isMoved, [.added, .removed, .modified].contains(kind) { return NSColor.systemBlue.withAlphaComponent(0.12) }
        return switch kind {
        case .context: nil
        case .added: NSColor.systemGreen.withAlphaComponent(0.16)
        case .removed: NSColor.systemRed.withAlphaComponent(0.16)
        case .modified: side == .old ? NSColor.systemRed.withAlphaComponent(0.16) : NSColor.systemGreen.withAlphaComponent(0.16)
        case .filler: textColor.withAlphaComponent(0.06)
        case .gap: textColor.withAlphaComponent(0.04)
        case .header: textColor.withAlphaComponent(0.1)
        }
    }

    package func emphasis(for kind: RowKind, side: RenderedSide) -> NSColor {
        switch kind {
        case .added: NSColor.systemGreen.withAlphaComponent(0.4)
        case .removed: NSColor.systemRed.withAlphaComponent(0.4)
        case .modified: side == .old ? NSColor.systemRed.withAlphaComponent(0.4) : NSColor.systemGreen.withAlphaComponent(0.4)
        case .context, .filler, .gap, .header: .clear
        }
    }

    /// Context is faint. Inline, every change shares one color so the strip reads as a map of where changes are;
    /// a pane of the split view shows its own side's color.
    package func minimapColor(for kind: RowKind, side: RenderedSide) -> NSColor? {
        switch (kind, side) {
        case (.context, _): textColor.withAlphaComponent(0.25)
        case (.filler, _), (.gap, _): nil
        case (.header, _): textColor.withAlphaComponent(0.6)
        case (.added, .unified), (.removed, .unified), (.modified, .unified): .controlAccentColor
        case (.added, _): .systemGreen
        case (.removed, _): .systemRed
        case (.modified, .old): .systemRed
        case (.modified, .new): .systemGreen
        }
    }

    /// The pane's monospaced face, two points smaller, so numbers line up in columns and read as part of the text.
    package var gutterFont: NSFont {
        let size = max(font.pointSize - 2, 9)
        return NSFont(descriptor: font.fontDescriptor, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Width of the text container that wraps at `column` characters of `font`, plus the line fragment padding.
    package static func wrapWidth(column: Int, font: NSFont, padding: CGFloat) -> CGFloat {
        CGFloat(column) * ("0" as NSString).size(withAttributes: [.font: font]).width + 2 * padding
    }
}
