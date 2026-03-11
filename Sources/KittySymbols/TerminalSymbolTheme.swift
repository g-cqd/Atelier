import Foundation

public struct TerminalSymbolTheme: Sendable {
    public enum Role: String, Sendable, CaseIterable {
        case project
        case panel
        case folderClosed
        case folderOpen
        case file
        case modeTree
        case modeEdit
        case search
        case status
        case warning
        case position
        case dimensions
        case gitBranch
        case gitModified
        case gitAdded
        case gitUntracked
        case gitDeleted
        case gitConflicted
        case dirty
        case close
        case explorer
        case openDocuments
    }

    public struct Glyph: Sendable, Equatable {
        public let text: String
        public let prefersSymbol: Bool

        public init(text: String, prefersSymbol: Bool) {
            self.text = text
            self.prefersSymbol = prefersSymbol
        }
    }

    private let glyphs: [Role: Glyph]

    public init(glyphs: [Role: Glyph]) {
        self.glyphs = glyphs
    }

    public subscript(_ role: Role) -> Glyph {
        glyphs[role] ?? Glyph(text: "", prefersSymbol: false)
    }

    public static func make(symbolsEnabled: Bool, catalog: SymbolCatalog?) -> TerminalSymbolTheme {
        let useSymbols = symbolsEnabled && TerminalSymbolSupport.prefersSFSymbolGlyphs()
        return TerminalSymbolTheme(glyphs: Role.allCases.reduce(into: [:]) { result, role in
            let fallback = fallbackText(for: role)
            if useSymbols,
               let name = symbolName(for: role),
               let entry = catalog?[name],
               let glyph = entry.glyph
            {
                result[role] = Glyph(text: glyph, prefersSymbol: true)
            } else {
                result[role] = Glyph(text: fallback, prefersSymbol: false)
            }
        })
    }

    private static func symbolName(for role: Role) -> String? {
        switch role {
        case .project:
            return "sidebar.left"
        case .panel:
            return "line.3.horizontal"
        case .folderClosed:
            return "folder"
        case .folderOpen:
            return "folder.badge.minus"
        case .file:
            return "doc"
        case .modeTree:
            return "list.bullet.indent"
        case .modeEdit:
            return "pencil"
        case .search:
            return "magnifyingglass"
        case .status:
            return "location"
        case .warning:
            return "exclamationmark.triangle"
        case .position:
            return "cursorarrow"
        case .dimensions:
            return "arrow.up.left.and.arrow.down.right"
        case .gitBranch:
            return "arrow.triangle.branch"
        case .gitModified:
            return "pencil.circle"
        case .gitAdded:
            return "plus.circle"
        case .gitUntracked:
            return "questionmark.circle"
        case .gitDeleted:
            return "minus.circle"
        case .gitConflicted:
            return "exclamationmark.triangle"
        case .dirty:
            return "circle"
        case .close:
            return "xmark"
        case .explorer:
            return "folder"
        case .openDocuments:
            return "doc.text"
        }
    }

    private static func fallbackText(for role: Role) -> String {
        switch role {
        case .project:
            return "[root]"
        case .panel:
            return "[tree]"
        case .folderClosed:
            return ">"
        case .folderOpen:
            return "v"
        case .file:
            return "-"
        case .modeTree:
            return "TREE"
        case .modeEdit:
            return "EDIT"
        case .search:
            return "/"
        case .status:
            return "i"
        case .warning:
            return "!"
        case .position:
            return "@"
        case .dimensions:
            return "#"
        case .gitBranch:
            return "\u{e0a0}"
        case .gitModified:
            return "M"
        case .gitAdded:
            return "A"
        case .gitUntracked:
            return "?"
        case .gitDeleted:
            return "D"
        case .gitConflicted:
            return "!"
        case .dirty:
            return "●"
        case .close:
            return "×"
        case .explorer:
            return "F"
        case .openDocuments:
            return "O"
        }
    }
}
