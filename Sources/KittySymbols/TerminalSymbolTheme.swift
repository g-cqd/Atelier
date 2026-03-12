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
        return TerminalSymbolTheme(
            glyphs: Role.allCases.reduce(into: [:]) { result, role in
                let fallback = fallbackText(for: role)
                if useSymbols,
                    let name = symbolName(for: role),
                    let glyph = resolveGlyph(name: name, catalog: catalog)
                {
                    result[role] = Glyph(text: glyph, prefersSymbol: true)
                } else {
                    result[role] = Glyph(text: fallback, prefersSymbol: false)
                }
            })
    }

    private static func resolveGlyph(name: String, catalog: SymbolCatalog?) -> String? {
        if let cp = puaCodepoints[name], let scalar = UnicodeScalar(cp) {
            return String(Character(scalar))
        }
        return catalog?[name]?.glyph
    }

    // SF Pro PUA codepoints for symbols used by the theme.
    // Discovered via bitmap comparison between NSImage(systemSymbolName:)
    // renderings and CTFont PUA glyph renderings at 128x128 resolution.
    private static let puaCodepoints: [String: UInt32] = [
        "folder": 0x1003ED,
        "folder.badge.minus": 0x100A9B,
        "document": 0x1018F6,
        "document.on.document": 0x101E62,
        "sidebar.left": 0x1014A2,
        "line.3.horizontal": 0x100962,
        "list.bullet.indent": 0x101292,
        "pencil": 0x10020A,
        "magnifyingglass": 0x1002AB,
        "location": 0x1002D1,
        "exclamationmark.triangle": 0x1001FE,
        "cursorarrow.rays": 0x1001F0,
        "arrow.up.left.and.arrow.down.right": 0x10014A,
        "arrow.trianglehead.branch": 0x100660,
        "pencil.circle": 0x10020B,
        "plus.circle": 0x10004C,
        "questionmark.circle": 0x10005C,
        "minus.circle": 0x10004E,
        "circle": 0x100000,
        "xmark": 0x100184,
    ]

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
            return "document"
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
            return "cursorarrow.rays"
        case .dimensions:
            return "arrow.up.left.and.arrow.down.right"
        case .gitBranch:
            return "arrow.trianglehead.branch"
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
            return "document.on.document"
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
