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

    var color: Color {
        switch self {
            case .added: .green
            case .deleted: .red
            case .modified: .orange
            case .renamed: .purple
        }
    }

    var nsColor: NSColor {
        switch self {
            case .added: .systemGreen
            case .deleted: .systemRed
            case .modified: .systemOrange
            case .renamed: .systemPurple
        }
    }

    static let size: CGFloat = 18
    static let cornerRadius: CGFloat = 4
}

/// A letter badge for the kind of change, with line counts where they mean something.
struct ChangeBadge: View {
    let summary: FileChangeSummary

    var body: some View {
        let glyph = ChangeGlyph(summary.kind)
        HStack(spacing: 6) {
            if showsCounts {
                Text("+\(summary.addedLines)")
                    .foregroundStyle(.green)
                Text("−\(summary.removedLines)")
                    .foregroundStyle(.red)
            }
            ChangeGlyphBadge(glyph: glyph)
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

/// The letter alone, the square everything else is built around.
struct ChangeGlyphBadge: View {
    let glyph: ChangeGlyph

    var body: some View {
        Text(glyph.letter)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: ChangeGlyph.size, height: ChangeGlyph.size)
            .background(RoundedRectangle(cornerRadius: ChangeGlyph.cornerRadius).fill(glyph.color))
    }
}

/// The same badge for AppKit rows: the explorer draws thousands of them, so it stays a plain view.
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

    override var intrinsicContentSize: NSSize {
        NSSize(width: ChangeGlyph.size, height: ChangeGlyph.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let glyph else { return }
        let alpha: CGFloat = isDimmed ? 0.35 : 1
        glyph.nsColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: ChangeGlyph.cornerRadius, yRadius: ChangeGlyph.cornerRadius).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha)
        ]
        let text = NSAttributedString(string: glyph.letter, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
