public enum FocusRegion: Sendable, Equatable, Hashable {
    case activityBar
    case sidebar
    case editor
    case searchPanel
    case tabRibbon
    case statusBar
    case overlay
    case custom(String)
}
