package import AppKit
package import AtelierSyntaxModel
package import AtelierTheme
package import DiffCore
import DiffGit
import Foundation

package enum RenderedSide: Sendable, Hashable {
    case unified
    case old
    case new
}

/// The colours a diff's changes take (book D18): the app's red and green, or Xcode's gray and blue.
package enum DiffColors: String, CaseIterable, Identifiable, Sendable {
    /// Removed lines red and added ones green.
    case standard
    /// Xcode's source control colours: removed lines gray, added ones blue, changed tokens tan and blue, and a blue
    /// change bar in the gutter.
    case xcode

    package var id: String { rawValue }
}

/// Colors and font of the diff panes: the system look, or one derived from an Xcode theme.
package struct DiffPalette: @unchecked Sendable, Equatable {
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
    /// The colours changes take (book D18).
    package let diffColors: DiffColors
    private let roleColors: [HighlightRole: NSColor]

    package static let system = DiffPalette(
        font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        textColor: .labelColor,
        background: .textBackgroundColor,
        selection: .selectedTextBackgroundColor,
        gutterBackground: .windowBackgroundColor,
        gutterText: .tertiaryLabelColor,
        gutterChangedText: .labelColor,
        lineHeightMultiple: 1,
        roleColors: [
            .keyword: .systemPink, .string: .systemRed, .comment: .secondaryLabelColor, .number: .systemBlue,
            .type: .systemTeal, .attribute: .systemOrange, .tag: .systemBlue, .property: .systemPurple,
            .escape: .systemOrange
        ]
    )

    private init(
        font: NSFont, textColor: NSColor, background: NSColor, selection: NSColor, gutterBackground: NSColor,
        gutterText: NSColor, gutterChangedText: NSColor, lineHeightMultiple: Double,
        roleColors: [HighlightRole: NSColor], diffColors: DiffColors = .standard
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
        self.roleColors = roleColors
        self.diffColors = diffColors
    }

    /// This palette with changes in `diffColors`.
    package func with(diffColors: DiffColors) -> DiffPalette {
        guard diffColors != self.diffColors else { return self }
        return DiffPalette(
            font: font, textColor: textColor, background: background, selection: selection,
            gutterBackground: gutterBackground, gutterText: gutterText, gutterChangedText: gutterChangedText,
            lineHeightMultiple: lineHeightMultiple, roleColors: roleColors, diffColors: diffColors)
    }

    /// The colours a theme states for its roles; a role the theme leaves out resolves through the theme's own
    /// hierarchy fallback, down to the plain text.
    package init(theme: SyntaxTheme) {
        let text = theme.plainText.foreground.map(NSColor.init) ?? Self.system.textColor
        let background = theme.background.map(NSColor.init) ?? Self.system.background
        var roles: [HighlightRole: NSColor] = [:]
        for role in HighlightRole.allCases {
            if let foreground = theme.style(for: role).foreground { roles[role] = NSColor(foreground) }
        }
        self.init(
            font: theme.font.flatMap(NSFont.init) ?? Self.system.font,
            textColor: text,
            background: background,
            selection: theme.selection.map(NSColor.init) ?? text.withAlphaComponent(0.2),
            gutterBackground: background.blended(withFraction: 0.04, of: text) ?? background,
            gutterText: text.withAlphaComponent(0.4),
            gutterChangedText: text,
            lineHeightMultiple: theme.lineHeightMultiple ?? 1,
            roleColors: roles
        )
    }

    /// The colour of a role: its own, else its parent's, else the plain text colour.
    package func color(for role: HighlightRole) -> NSColor {
        var current: HighlightRole? = role
        while let candidate = current {
            if let color = roleColors[candidate] { return color }
            current = candidate.parent
        }
        return textColor
    }

    package func rowBackground(for kind: RowKind, side: RenderedSide, isMoved: Bool = false) -> NSColor? {
        if isMoved, [.added, .removed, .modified].contains(kind) { return NSColor.systemBlue.withAlphaComponent(0.12) }
        return switch kind {
            case .context: nil
            case .added: addedBackground
            case .removed: removedBackground
            case .modified: side == .old ? removedBackground : addedBackground
            case .filler: textColor.withAlphaComponent(0.06)
            case .header: textColor.withAlphaComponent(0.1)
        }
    }

    package func emphasis(for kind: RowKind, side: RenderedSide) -> NSColor {
        switch kind {
            case .added: addedEmphasis
            case .removed: removedEmphasis
            case .modified: side == .old ? removedEmphasis : addedEmphasis
            case .context, .filler, .header: .clear
        }
    }

    /// Behind a removed line: red, or Xcode's gray (image 12).
    private var removedBackground: NSColor {
        diffColors == .xcode ? textColor.withAlphaComponent(0.07) : NSColor.systemRed.withAlphaComponent(0.16)
    }

    /// Behind an added line: green, or Xcode's light blue.
    private var addedBackground: NSColor {
        diffColors == .xcode
            ? NSColor.systemBlue.withAlphaComponent(0.12) : NSColor.systemGreen.withAlphaComponent(0.16)
    }

    /// Behind a changed token of a removed line: red, or Xcode's tan.
    private var removedEmphasis: NSColor {
        diffColors == .xcode
            ? NSColor.systemOrange.withAlphaComponent(0.28) : NSColor.systemRed.withAlphaComponent(0.4)
    }

    /// Behind a changed token of an added line: green, or Xcode's blue.
    private var addedEmphasis: NSColor {
        diffColors == .xcode ? NSColor.systemBlue.withAlphaComponent(0.3) : NSColor.systemGreen.withAlphaComponent(0.4)
    }

    /// Xcode's change bar, down the gutter's leading edge beside every changed row (book D18); nil in the app's own
    /// colours, which have none.
    package var changeBar: NSColor? {
        diffColors == .xcode ? .systemBlue : nil
    }

    /// Context is faint. Inline, every change shares one color so the strip reads as a map of where changes are;
    /// a pane of the split view shows its own side's color.
    package func minimapColor(for kind: RowKind, side: RenderedSide) -> NSColor? {
        switch (kind, side) {
            case (.context, _): textColor.withAlphaComponent(0.25)
            case (.filler, _): nil
            case (.header, _): textColor.withAlphaComponent(0.6)
            case (.added, .unified), (.removed, .unified), (.modified, .unified): .controlAccentColor
            case (.added, _), (.modified, .new): diffColors == .xcode ? .systemBlue : .systemGreen
            case (.removed, _), (.modified, .old):
                diffColors == .xcode ? textColor.withAlphaComponent(0.45) : .systemRed
        }
    }

    /// The colour of the gutter's marker for a change of the compact inline view (book DIFF-04): green for an addition,
    /// red for a removal, and blue for a modification, as Xcode's change bar.
    package func changeMarker(for kind: RenderedChange.Kind) -> NSColor {
        switch kind {
            case .added: .systemGreen
            case .removed: .systemRed
            case .modified: .systemBlue
        }
    }

    /// The hairline that separates the two halves of a gap's handle, across the gutter and the text alike (book
    /// DIFF-02): Xcode's, 241 on its white gutter.
    package var gapSeparator: NSColor {
        textColor.withAlphaComponent(0.055)
    }

    /// The pane's monospaced face, two points smaller, so numbers line up in columns and read as part of the text.
    package var gutterFont: NSFont {
        let size = max(font.pointSize - 2, 9)
        return NSFont(descriptor: font.fontDescriptor, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Width of the text container that wraps at `column` characters of `font`, plus the line fragment padding.
    package static func wrapWidth(column: Int, font: NSFont, padding: CGFloat) -> CGFloat {
        CGFloat(column) * ("0" as NSString).size(withAttributes: [.font: font]).width + 2 * padding
    }
}

extension NSColor {
    /// The theme's sRGB components.
    package convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension SyntaxTheme {
    /// The background's luminance with ITU-R BT.601 weights, 0 black to 1 white; nil when the theme sets none.
    package var backgroundLuminance: Double? {
        background.map { 0.299 * Double($0.red) + 0.587 * Double($0.green) + 0.114 * Double($0.blue) }
    }
}

extension NSFont {
    /// The font the descriptor names, when it is installed.
    package convenience init?(_ descriptor: FontDescriptor) {
        self.init(name: descriptor.postScriptName, size: descriptor.size)
    }
}
