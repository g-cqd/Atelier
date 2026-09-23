import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The letter, colour and name of a kind of change: one vocabulary for the card badges and the explorer rows.
enum ChangeGlyph {
    case added
    case deleted
    case modified
    case renamed

    init(_ kind: FileChangeSummary.Kind) {
        self =
            switch kind {
                case .added: .added
                case .deleted: .deleted
                case .modified: .modified
                case .renamed: .renamed
            }
    }

    /// Nil for an identical path, which gets no badge.
    init?(_ status: PathStatus) {
        switch status {
            case .same: return nil
            case .different: self = .modified
            case .onlyLeft: self = .deleted
            case .onlyRight: self = .added
            case .renamed: self = .renamed
        }
    }

    var letter: String {
        switch self {
            case .added: "A"
            case .deleted: "D"
            case .modified: "M"
            case .renamed: "R"
        }
    }

    var title: String {
        switch self {
            case .added: "Added"
            case .deleted: "Deleted"
            case .modified: "Modified"
            case .renamed: "Renamed"
        }
    }

    /// This kind's colour under `scheme`, the one its badge draws in.
    func color(in scheme: BadgeScheme) -> Color {
        BadgeStyleResolver.colorToken(for: badgeKind, scheme: scheme).color
    }

    /// This kind, in the scheme-and-state-independent vocabulary ``BadgeStyleResolver`` resolves from.
    var badgeKind: BadgeChangeKind {
        switch self {
            case .added: .added
            case .deleted: .deleted
            case .modified: .modified
            case .renamed: .renamed
        }
    }

    static let size: CGFloat = 18
    static let cornerRadius: CGFloat = 4
}

extension BadgeColorToken {
    var color: Color {
        switch self {
            case .green: .green
            case .blue: .blue
            case .red: .red
            case .orange: .orange
            case .purple: .purple
        }
    }

    var nsColor: NSColor {
        switch self {
            case .green: .systemGreen
            case .blue: .systemBlue
            case .red: .systemRed
            case .orange: .systemOrange
            case .purple: .systemPurple
        }
    }
}

/// A letter badge for the kind of change, with line counts where they mean something.
struct ChangeBadge: View {
    let summary: FileChangeSummary
    var scheme: BadgeScheme = .classic
    var state: BadgeChangeState = .staged

    var body: some View {
        let glyph = ChangeGlyph(summary.kind)
        HStack(spacing: 6) {
            if showsCounts {
                Text("+\(summary.addedLines)")
                    .foregroundStyle(.green)
                Text("−\(summary.removedLines)")
                    .foregroundStyle(.red)
            }
            ChangeGlyphBadge(glyph: glyph, scheme: scheme, state: state)
                .help(title)
        }
        .font(.caption.monospacedDigit())
    }

    private var showsCounts: Bool {
        switch summary.kind {
            case .added, .deleted: false
            case .modified: true
            case .renamed: summary.addedLines + summary.removedLines > 0
        }
    }

    private var title: String {
        if case .renamed(let path) = summary.kind { return "Renamed to \(path)" }
        return ChangeGlyph(summary.kind).title
    }
}

/// The letter alone, the square everything else is built around. Defaults reproduce today's look exactly --
/// classic colours, filled -- so a card header or a toolbar label that never passes ``scheme``/``state`` keeps
/// drawing exactly as it always has; only the explorer's rows opt into the state-aware, scheme-aware look.
struct ChangeGlyphBadge: View {
    let glyph: ChangeGlyph
    var scheme: BadgeScheme = .classic
    var state: BadgeChangeState = .staged
    var isSelected = false
    var isFocused = false
    /// The badge's side; the letter and the corner radius scale with it, the outline stays 1 pt.
    var size: CGFloat = ChangeGlyph.size

    var body: some View {
        let style = BadgeStyleResolver.resolve(
            scheme: scheme, kind: glyph.badgeKind, state: state, isSelected: isSelected, isFocused: isFocused)
        let scale = size / ChangeGlyph.size
        let shape = RoundedRectangle(cornerRadius: ChangeGlyph.cornerRadius * scale)
        Text(glyph.letter)
            .font(.system(size: 10 * scale, weight: .bold))
            .foregroundStyle(style.text.color)
            .frame(width: size, height: size)
            .background(shape.fill(style.fill.color))
            .overlay {
                if let stroke = style.stroke {
                    shape.strokeBorder(stroke.color, lineWidth: 1)
                }
            }
    }
}

extension BadgeFill {
    fileprivate var color: Color {
        switch self {
            case .none: .clear
            case .token(let token): token.color
            case .white: .white
        }
    }
}

extension BadgeInk {
    fileprivate var color: Color {
        switch self {
            case .white: .white
            case .token(let token): token.color
            case .primary: .primary
        }
    }

    fileprivate var nsColor: NSColor {
        switch self {
            case .white: .white
            case .token(let token): token.nsColor
            case .primary: .labelColor
        }
    }
}

/// The same badge for AppKit rows: the explorer draws thousands of them, so it stays a plain view.
///
/// Its host cell sets ``backgroundStyle``: `.emphasized` exactly while the row is selected in a focused list, the
/// native accent-versus-gray distinction the badge's white variant follows.
final class ChangeBadgeView: NSView {
    var glyph: ChangeGlyph? {
        didSet {
            isHidden = glyph == nil
            needsDisplay = true
        }
    }

    /// Folders carry the aggregate of their files, drawn lighter so the files stand out.
    var isDimmed = false {
        didSet { needsDisplay = true }
    }

    var scheme: BadgeScheme = .classic {
        didSet { needsDisplay = true }
    }

    /// Where this row's change stands against the index; see ``BadgeChangeState``.
    var state: BadgeChangeState = .staged {
        didSet { needsDisplay = true }
    }

    @objc dynamic var backgroundStyle: NSView.BackgroundStyle = .normal {
        didSet {
            guard oldValue != backgroundStyle else { return }
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ChangeGlyph.size, height: ChangeGlyph.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let glyph else { return }
        let alpha: CGFloat = isDimmed ? 0.35 : 1
        let isEmphasizedSelection = backgroundStyle == .emphasized
        let style = BadgeStyleResolver.resolve(
            scheme: scheme, kind: glyph.badgeKind, state: state, isSelected: isEmphasizedSelection,
            isFocused: isEmphasizedSelection)
        let path = NSBezierPath(
            roundedRect: bounds, xRadius: ChangeGlyph.cornerRadius, yRadius: ChangeGlyph.cornerRadius)
        switch style.fill {
            case .none: break
            case .token(let token):
                token.nsColor.withAlphaComponent(alpha).setFill()
                path.fill()
            case .white:
                NSColor.white.withAlphaComponent(alpha).setFill()
                path.fill()
        }
        if let stroke = style.stroke {
            // Inset by half the line width so the 1 pt outline stays inside the badge's own bounds.
            let strokePath = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: ChangeGlyph.cornerRadius - 0.5,
                yRadius: ChangeGlyph.cornerRadius - 0.5)
            stroke.nsColor.withAlphaComponent(alpha).setStroke()
            strokePath.lineWidth = 1
            strokePath.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: style.text.nsColor.withAlphaComponent(alpha)
        ]
        let text = NSAttributedString(string: glyph.letter, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
