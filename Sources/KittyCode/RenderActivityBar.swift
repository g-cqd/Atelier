import KittyCodecs
import KittyRenderer
import KittySymbols
import KittyWidgets

@MainActor
func renderActivityBar(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    colorScheme: EditorState.ColorScheme
) {
    guard state.config.activityBar.show else { return }

    let items: [ActivityBar.Item] = state.config.activityBar.items.map { id in
        let icon: String
        switch id {
        case "explorer":
            icon = state.symbolTheme[.explorer].text
        case "openDocuments":
            icon = state.symbolTheme[.openDocuments].text
        default:
            icon = "?"
        }
        return ActivityBar.Item(icon: icon, id: id)
    }

    let activeIdx: Int
    switch state.activeSidebarPanel {
    case .explorer:
        activeIdx = state.config.activityBar.items.firstIndex(of: "explorer") ?? 0
    case .openDocuments:
        activeIdx = state.config.activityBar.items.firstIndex(of: "openDocuments") ?? 0
    }

    var barStyle = ActivityBar.ActivityBarStyle()
    if let fg = state.config.theme.activityBarForeground {
        barStyle.normalStyle = Style(fg: fg.color)
    }
    if let fg = state.config.theme.activityBarActiveForeground {
        barStyle.activeStyle = Style(fg: fg.color, bold: true)
    }

    let bar = ActivityBar(items: items, activeIndex: activeIdx, style: barStyle)
    bar.render(to: &pipeline.buffer, in: rect)
}
