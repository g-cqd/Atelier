package import AppKit
import Foundation

/// The hover panel's type scale: the prose size, and the title and heading sizes above it, largest first.
package enum HoverTypography {
    package static let bodySize: CGFloat = 12
    /// The symbol's name above its abstract.
    package static var title: NSFont { .systemFont(ofSize: 16, weight: .bold) }

    /// A heading's size and weight: levels 1 to 3 each distinct and larger than the prose, deeper levels at its size.
    package static func heading(level: Int) -> (size: CGFloat, weight: NSFont.Weight) {
        switch level {
            case ...1: (15, .bold)
            case 2: (14, .bold)
            case 3: (13, .semibold)
            default: (bodySize, .semibold)
        }
    }
}

extension HoverDocument {
    /// One styled block of a document's discussion, laid out on its own.
    ///
    /// `@unchecked Sendable`: every stored `NSAttributedString` is built once and never mutated.
    package indirect enum Block: @unchecked Sendable {
        case paragraph(NSAttributedString)
        case heading(level: Int, text: NSAttributedString)
        /// Colored by the hovered pane's palette; every line and its indentation as the source had them.
        case code(NSAttributedString)
        /// Each item is its own blocks; `start` numbers an ordered list's first item.
        case list(ordered: Bool, start: Int, items: [[Block]])
        case quote([Block])
        case rule
    }

    /// `markdown`'s blocks, styled for the panel: prose as the abstract is, headings at their level's size, and code
    /// colored by `palette` as the fence's language, Swift when the fence names none.
    package static func blocks(fromMarkdown markdown: String, palette: DiffPalette) -> [Block] {
        HoverMarkdownBlock.parse(markdown).map { styled($0, palette: palette) }
    }

    private static func styled(_ block: HoverMarkdownBlock, palette: DiffPalette) -> Block {
        switch block {
            case .paragraph(let text):
                return .paragraph(styledInline(text, size: HoverTypography.bodySize, weight: .regular))
            case .heading(let level, let text):
                let (size, weight) = HoverTypography.heading(level: level)
                return .heading(level: level, text: styledInline(text, size: size, weight: weight))
            case .code(let language, let text):
                return .code(CodeAttributedBuilder.attributedString(for: text, languageTag: language, palette: palette))
            case .list(let ordered, let start, let items):
                return .list(
                    ordered: ordered, start: start,
                    items: items.map { item in item.map { styled($0, palette: palette) } })
            case .quote(let blocks):
                return .quote(blocks.map { styled($0, palette: palette) })
            case .thematicBreak:
                return .rule
        }
    }
}
