// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_body_length
import AtelierTheme
import Foundation
import KittyCodecs
import KittySyntax
import KittyWidgets

extension EditorState {
    public static func makeColorScheme(config: KittyConfig) -> ColorScheme {
        let theme = config.theme
        let whitespaceDefault = ColorRGB(r: 0x48, g: 0x4f, b: 0x58)
        let scrollTrack = Style(fg: .rgb(r: 60, g: 60, b: 60), dim: true)
        let scrollThumb = Style(fg: .rgb(r: 140, g: 140, b: 140), dim: true)
        let cursorLineStyle =
            if config.editor.highlightCurrentLine {
                Style(
                    fg: theme.cursorLineForeground?.color ?? .default,
                    bg: (theme.cursorLineBackground ?? theme.separatorForeground).color
                )
            } else {
                Style()
            }
        return ColorScheme(
            bg: Style(),
            treeBg: Style(fg: theme.treePanelForeground.color),
            treeSelected: Style(fg: theme.treeSelectedForeground.color, bold: true),
            treeDir: Style(fg: theme.treeDirectoryForeground.color, bold: true),
            lineNumber: Style(fg: theme.lineNumberForeground.color),
            editorText: Style(fg: theme.editorForeground.color),
            editorCursorLine: cursorLineStyle,
            gitModifiedLine: makeGitLineOverlay(
                foreground: theme.gitModifiedLineForeground
                    ?? ColorOverlayConfig(color: theme.gitModifiedForeground, alpha: 0.45),
                background: theme.gitModifiedLineBackground
                    ?? ColorOverlayConfig(color: theme.gitModifiedForeground, alpha: 0.18)
            ),
            gitAddedLine: makeGitLineOverlay(
                foreground: theme.gitAddedLineForeground
                    ?? ColorOverlayConfig(color: theme.gitAddedForeground, alpha: 0.45),
                background: theme.gitAddedLineBackground
                    ?? ColorOverlayConfig(color: theme.gitAddedForeground, alpha: 0.18)
            ),
            gitUntrackedLine: makeGitLineOverlay(
                foreground: theme.gitUntrackedLineForeground
                    ?? ColorOverlayConfig(color: theme.gitUntrackedForeground, alpha: 0.45),
                background: theme.gitUntrackedLineBackground
                    ?? ColorOverlayConfig(color: theme.gitUntrackedForeground, alpha: 0.18)
            ),
            gitDeletedLine: makeGitLineOverlay(
                foreground: theme.gitDeletedLineForeground
                    ?? ColorOverlayConfig(color: theme.gitDeletedForeground, alpha: 0.45),
                background: theme.gitDeletedLineBackground
                    ?? ColorOverlayConfig(color: theme.gitDeletedForeground, alpha: 0.18)
            ),
            gitConflictedLine: makeGitLineOverlay(
                foreground: theme.gitConflictedLineForeground
                    ?? ColorOverlayConfig(color: theme.gitConflictedForeground, alpha: 0.45),
                background: theme.gitConflictedLineBackground
                    ?? ColorOverlayConfig(color: theme.gitConflictedForeground, alpha: 0.18)
            ),
            statusBar: Style(fg: theme.statusBarForeground.color),
            titleBar: Style(fg: theme.titleBarForeground.color),
            separator: Style(fg: theme.separatorForeground.color),
            syntaxKeyword: Style(fg: theme.keywordForeground.color),
            syntaxType: Style(fg: theme.typeForeground.color),
            syntaxComment: Style(fg: theme.commentForeground.color, italic: true),
            syntaxString: Style(fg: theme.stringForeground.color),
            syntaxNumber: Style(fg: theme.numberForeground.color),
            syntaxAttribute: Style(fg: theme.attributeForeground.color),
            gitModified: Style(fg: theme.gitModifiedForeground.color),
            gitAdded: Style(fg: theme.gitAddedForeground.color),
            gitUntracked: Style(fg: theme.gitUntrackedForeground.color, dim: true),
            gitDeleted: Style(fg: theme.gitDeletedForeground.color),
            gitConflicted: Style(fg: theme.gitConflictedForeground.color, bold: true),
            whitespaceIndentation: Style(
                fg: (theme.whitespaceIndentationForeground ?? whitespaceDefault).color, dim: true),
            whitespaceSpace: Style(
                fg: (theme.whitespaceSpaceForeground ?? whitespaceDefault).color, dim: true),
            whitespaceLineBreak: Style(
                fg: (theme.whitespaceLineBreakForeground ?? whitespaceDefault).color, dim: true),
            whitespaceUnexpected: Style(
                fg: (theme.whitespaceUnexpectedForeground ?? ColorRGB(r: 0xff, g: 0x7b, b: 0x72))
                    .color),
            verticalScrollIndicator: VerticalScrollIndicatorStyle(
                trackStyle: scrollTrack,
                thumbStyle: scrollThumb,
                trackCharacter: " ",
                thumbCharacter: "\u{2593}"
            ),
            horizontalScrollIndicator: HorizontalScrollIndicatorStyle(
                trackStyle: scrollTrack,
                thumbStyle: scrollThumb,
                trackCharacter: " ",
                thumbCharacter: "\u{2501}"
            ),
            emptyEditorMessage: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            selection: Style(
                fg: theme.selectionForeground?.color ?? .default,
                bg: (theme.selectionBackground ?? ColorRGB(r: 0x26, g: 0x4f, b: 0x78)).color
            ),
            searchMatch: Style(
                fg: theme.searchMatchForeground?.color ?? .default,
                bg: (theme.searchMatchBackground ?? ColorRGB(r: 0x3a, g: 0x3d, b: 0x41)).color
            ),
            activeSearchMatch: Style(
                fg: theme.activeSearchMatchForeground?.color ?? .rgb(r: 0xff, g: 0xff, b: 0xff),
                bg: (theme.activeSearchMatchBackground ?? ColorRGB(r: 0x61, g: 0x4f, b: 0x0e)).color,
                bold: true
            ),
            commandFeedback: Style(
                fg: theme.commandFeedbackForeground?.color ?? .rgb(r: 0x8b, g: 0x94, b: 0x9e),
                bg: theme.commandFeedbackBackground?.color ?? .default,
                dim: true
            )
        )
    }

    private static func makeGitLineOverlay(
        foreground: ColorOverlayConfig,
        background: ColorOverlayConfig
    ) -> TextStyleOverlay {
        TextStyleOverlay(
            foreground: ColorOverlay(color: foreground.color.color, alpha: foreground.alpha),
            background: ColorOverlay(color: background.color.color, alpha: background.alpha)
        )
    }

    /// The syntax theme the config asks for beyond its own colours: the Xcode theme it names, else one derived
    /// from the terminal palette when `syntax.themeFromTerminal` is set and the palette has been answered.
    /// - Throws: The read or parse error of the `.xccolortheme` file.
    static func resolveConfiguredSyntaxTheme(config: KittyConfig, palette: TerminalPalette) throws -> Theme? {
        if let xcode = try loadXcodeTheme(config: config) { return xcode }
        guard config.syntax.themeFromTerminal, palette.foreground != nil || palette.background != nil else {
            return nil
        }
        return Theme(.derived(from: palette))
    }

    /// Feeds one undecoded terminal reply to the palette collector. Returns whether the bytes were a palette
    /// reply; the device-attributes reply that ends the round applies the derived theme when the config asks
    /// for it and no Xcode theme is set.
    @discardableResult
    public func receiveTerminalReply(_ bytes: [UInt8]) -> Bool {
        guard let reply = OSCPalette.parse(bytes) else { return false }
        switch reply {
            case .foreground(let color):
                terminalPalette.foreground = ThemeColor(color)
            case .background(let color):
                terminalPalette.background = ThemeColor(color)
            case .ansi(let index, let color):
                guard index < 256 else { return true }
                if terminalPalette.ansi.count <= index {
                    terminalPalette.ansi.append(
                        contentsOf: repeatElement(nil, count: index + 1 - terminalPalette.ansi.count))
                }
                terminalPalette.ansi[index] = ThemeColor(color)
            case .end:
                guard config.syntax.themeFromTerminal, config.syntax.xcodeTheme == nil else { return true }
                replaceConfiguredSyntaxTheme(Theme(.derived(from: terminalPalette)))
        }
        return true
    }

    /// The syntax theme `config.syntax.xcodeTheme` names, resolved to terminal styles; nil when none is set.
    /// - Throws: The read or parse error of the `.xccolortheme` file.
    static func loadXcodeTheme(config: KittyConfig) throws -> Theme? {
        guard let path = config.syntax.xcodeTheme, !path.isEmpty else { return nil }
        let url = URL(filePath: PathUtilities.expandingTilde(in: path))
        let document = try XcodeThemeDocument(contentsOf: url)
        return Theme(document.syntaxTheme(named: url.deletingPathExtension().lastPathComponent))
    }
}

extension ThemeColor {
    /// A theme colour from the terminal's 8-bit channels.
    init(_ color: ColorRGB) {
        self.init(byteRed: color.r, green: color.g, blue: color.b)
    }
}
