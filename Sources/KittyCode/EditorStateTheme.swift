import KittyCodecs

extension EditorState {
    static func makeColorScheme(config: KittyConfig) -> ColorScheme {
        let theme = config.theme
        return ColorScheme(
            bg: Style(),
            treeBg: Style(fg: theme.treePanelForeground.color),
            treeSelected: Style(fg: theme.treeSelectedForeground.color, bold: true),
            treeDir: Style(fg: theme.treeDirectoryForeground.color, bold: true),
            lineNumber: Style(fg: theme.lineNumberForeground.color),
            editorText: Style(fg: theme.editorForeground.color),
            editorCursorLine: Style(fg: theme.editorForeground.color),
            statusBar: Style(fg: theme.statusBarForeground.color),
            titleBar: Style(fg: theme.titleBarForeground.color),
            separator: Style(fg: theme.separatorForeground.color),
            syntaxKeyword: Style(fg: theme.keywordForeground.color),
            syntaxType: Style(fg: theme.typeForeground.color),
            syntaxComment: Style(fg: theme.commentForeground.color, italic: true),
            syntaxString: Style(fg: theme.stringForeground.color),
            syntaxNumber: Style(fg: theme.numberForeground.color),
            syntaxAttribute: Style(fg: theme.attributeForeground.color)
        )
    }
}