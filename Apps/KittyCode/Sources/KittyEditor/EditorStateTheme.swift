import KittyCodecs
import KittyWidgets

public extension EditorState {
    static func makeColorScheme(config: KittyConfig) -> ColorScheme {
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
}
