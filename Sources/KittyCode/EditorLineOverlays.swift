import KittyFileTree
import KittyWidgets

@MainActor
func activeLineStyleOverlays(
    state: EditorState,
    colorScheme: EditorState.ColorScheme
) -> [Int: TextStyleOverlay] {
    guard state.config.showGitStatus else { return [:] }
    guard state.config.gitDecorations.showLineBackgrounds || state.config.gitDecorations.showLineForegrounds else {
        return [:]
    }
    guard let decorations = state.bufferManager.activeBuffer?.gitLineDecorations.markers,
          !decorations.isEmpty
    else {
        return [:]
    }

    return decorations.reduce(into: [Int: TextStyleOverlay]()) { result, entry in
        let (lineIndex, color) = entry
        let overlay = filteredLineOverlay(
            colorScheme.gitLineOverlay(for: color),
            showForeground: state.config.gitDecorations.showLineForegrounds,
            showBackground: state.config.gitDecorations.showLineBackgrounds
        )
        if !overlay.isEmpty {
            result[lineIndex] = overlay
        }
    }
}

private func filteredLineOverlay(
    _ overlay: TextStyleOverlay,
    showForeground: Bool,
    showBackground: Bool
) -> TextStyleOverlay {
    TextStyleOverlay(
        foreground: showForeground ? overlay.foreground : nil,
        background: showBackground ? overlay.background : nil
    )
}
