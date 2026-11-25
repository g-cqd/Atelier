package import Foundation

/// Where panes say which rows of their text they show (perf11-viewport), so the stages after the text colour and
/// emphasize those first. A pane registers a way to read its rows when it shows a text, and the pipeline reads it when
/// it starts decorating the text, by then laid out in its window.
@MainActor
package final class DecorationViewport {
    private var readers: [UUID: () -> Range<Int>?] = [:]

    package init() {}

    /// Registers `rows`, which reads the rows of the text `textID` a pane shows, in place of any reader before.
    package func register(_ textID: UUID, rows: @escaping () -> Range<Int>?) {
        readers[textID] = rows
    }

    /// Forgets the reader of `textID`, as a pane that stops showing it does.
    package func unregister(_ textID: UUID) {
        readers[textID] = nil
    }

    /// The rows of `textID` a pane shows now; nil when no pane shows it, or it is not laid out yet.
    package func visibleRows(of textID: UUID) -> Range<Int>? {
        readers[textID]?()
    }
}
