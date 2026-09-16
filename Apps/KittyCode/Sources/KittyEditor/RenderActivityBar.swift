import KittyCodecs
public import KittyRenderer
import KittySymbols
public import KittyWidgets

@MainActor
public func renderActivityBar(
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
            case "search":
                icon = state.symbolTheme[.search].text
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
        case .search:
            activeIdx = state.config.activityBar.items.firstIndex(of: "search") ?? 0
    }

    let theme = state.config.theme
    var barStyle = ActivityBar.ActivityBarStyle()
    if let s = theme.resolvedStyle(theme.activityBarForeground) {
        barStyle.normalStyle = s
    }
    if let s = theme.resolvedStyle(theme.activityBarActiveForeground) {
        barStyle.activeStyle = s
    }

    let bar = ActivityBar(items: items, activeIndex: activeIdx, style: barStyle)
    bar.render(to: &pipeline.buffer, in: rect)
}
