import AemiCore
import AtelierHighlighting
package import DiffCore
import DiffGit
package import DiffRendering
package import Foundation

/// The stages after the text (PERF-09): once a pane shows a published file, its sides are coloured and its changes
/// emphasized, the moved lines found, each off the main actor, visible lines first, each within its deadline, and
/// landing on the main actor as `DiffDecorations` that change no layout. A stage that fails or runs out of time leaves
/// what it reached, and plain text beyond it.
extension RenderPipeline {
    /// Which stage a `.decorated` event reports.
    package enum DecorationLayer: Sendable, Hashable {
        /// A colour tier's tokens: the lexer's, swift-syntax's.
        case color(HighlightLayer)
        /// Intraline emphasis, and the moved lines.
        case marks
        /// A side's scopes, which the gutter's ribbon draws (DIFF-03).
        case scopes
    }

    /// How long finding a file's emphasis and moved lines may take (review §7.4: emphasis within 250 ms for an L file);
    /// past it, the changes it did not reach stay plain.
    package nonisolated static let marksDeadline = Duration.milliseconds(250)
    /// How many changes a marks job emphasizes between two landings, past the visible ones.
    nonisolated static let marksChunk = 64

    /// Whether displayed sides get the colour of the tiers after the lexer: swift-syntax's, and a language server's
    /// semantic colour. Turning it off stops every colour job and colours the panes with the lexer alone; turning it on
    /// colours the files on screen again, asking every tier afresh.
    package var refinesSwiftColor: Bool {
        get { decorator.refinesSwiftColor }
        set {
            guard newValue != decorator.refinesSwiftColor else { return }
            decorator.refinesSwiftColor = newValue
            decorator.resetColors()
            decorator.publish(publishedFiles().map { ($0.rendered, $0.composition) })
            for id in decorator.displayedFiles { decorateDisplayed(id) }
        }
    }

    /// Where panes report the rows they show.
    package var decorationViewport: DecorationViewport { decorator.viewport }

    /// The decorations of the published text `id`, for the pane that shows it; nil while none has landed.
    package func decorations(forText id: UUID) -> DiffDecorations? {
        decorator.byText[id]
    }

    /// Starts the stages after the text on the published file `id`, which a pane now shows: each side's colour, unless
    /// its content is coloured or being coloured already, and the file's emphasis and moved lines, unless found or being
    /// found. What landed already reaches the file's panes at once.
    package func decorateDisplayed(_ id: RenderedDiff.ID) {
        let files = publishedFiles()
        decorator.noteDisplayed(id, published: Set(files.map(\.rendered.id)))
        decorator.cancel(
            keepingColors: Set(files.flatMap { [$0.composition.old, $0.composition.new] }.compactMap(\.self)),
            marks: Set(files.map(\.diff.id)))
        if let file = files.first(where: { $0.rendered.id == id }) {
            for side in [RenderedSide.old, .new] {
                startColors(side, of: file)
                startScopes(side, of: file)
            }
            startMarks(of: file)
        }
        decorator.publish(files.map { ($0.rendered, $0.composition) })
    }

    /// Gives every published text the decorations found for its content, and drops those of texts no longer published:
    /// what is published changed, by a render, a relayout or a gap drag.
    func refreshDecorations() {
        decorator.publish(publishedFiles().map { ($0.rendered, $0.composition) })
    }

    /// A published file: what shows, what it was prepared from, and its parts.
    struct PublishedFile {
        let rendered: RenderedDiff
        let diff: PreparedDiff
        let composition: DiffDecorator.Composition
    }

    func publishedFiles() -> [PublishedFile] {
        guard let target else { return [] }
        let rendered: [RenderedDiff] =
            switch target {
                case .file: file.map { [$0] } ?? []
                case .cards: cards.map(\.rendered)
            }
        return zip(rendered, zip(prepared, target.pairs))
            .map { rendered, prepared in
                let (diff, pair) = prepared
                return PublishedFile(
                    rendered: rendered, diff: diff,
                    composition: DiffDecorator.Composition(
                        preparation: diff.id, old: colorKey(of: pair.old, side: .old, in: diff),
                        new: colorKey(of: pair.new, side: .new, in: diff)))
            }
    }

    /// The key a side is coloured under; nil when the side is absent or empty, or no tier colours its language.
    private func colorKey(of entry: SourceEntry?, side: RenderedSide, in diff: PreparedDiff)
        -> DiffDecorator.ContentKey?
    {
        guard let entry, !(side == .old ? diff.oldText : diff.newText).isEmpty,
            !decorator.activeTiers(for: diff.language).isEmpty
        else { return nil }
        if let blob = entry.blobID { return .blob(blob, diff.language) }
        return .preparation(diff.id, side)
    }

    /// Sends `.decorated` for each published file with the content of `composition` or of `preparation`.
    func sendDecorated(_ layer: DecorationLayer, where shows: (PublishedFile) -> Bool) {
        for file in publishedFiles() where shows(file) { onEvent?(.decorated(file.rendered.id, layer)) }
    }

    // MARK: Colour

    /// Runs the tier job on one side of `file`, unless its content is coloured already or being coloured: each update
    /// lands on the main actor as it comes, the lines a pane shows first.
    private func startColors(_ side: RenderedSide, of file: PublishedFile) {
        guard let key = side == .old ? file.composition.old : file.composition.new, !decorator.isColored(key) else {
            return
        }
        let diff = file.diff
        let text = side == .old ? diff.oldText : diff.newText
        let lines = side == .old ? diff.model.oldLines : diff.model.newLines
        let request = TierRequest(
            revision: Self.revision(of: key, path: diff.title, language: diff.language), text: text,
            lineRanges: DiffRenderer.lineRanges(of: text, lines: lines),
            visibleLines: visibleLines(of: side, in: file) ?? Self.linesAroundFirstChange(of: side, in: diff),
            unit: .utf16)
        let stamp = DiffDecorator.Stamp(generation: generation, fileID: file.rendered.id)
        let lineCount = lines.count
        let tiers = decorator.activeTiers(for: diff.language)
        let clock = decorator.clock
        decorator.trackColors(
            taskProvider.task(priority: .utility) {
                await HighlightTiers.run(request, tiers: tiers, clock: clock) { event in
                    guard case .update(let update) = event else { return }
                    await self.land(update, lineCount: lineCount, key: key, stamp: stamp)
                }
                self.decorator.endColors(key, cancelled: Task.isCancelled)
            }, for: key)
    }

    /// Takes a tier's update, unless its job was cancelled, or its render was superseded and no published file shows
    /// its content any more; then decorates every published text that shows it.
    private func land(_ update: TierUpdate, lineCount: Int, key: DiffDecorator.ContentKey, stamp: DiffDecorator.Stamp) {
        let files = publishedFiles()
        let shows = { (file: PublishedFile) in file.composition.old == key || file.composition.new == key }
        let isShown = files.contains { $0.rendered.id == stamp.fileID || shows($0) }
        guard !Task.isCancelled, stamp.generation == generation || isShown else { return }
        guard update.layer == .lexical || decorator.refinesSwiftColor else { return }
        decorator.land(update, lineCount: lineCount, for: key)
        decorator.publish(files.map { ($0.rendered, $0.composition) })
        sendDecorated(.color(update.layer), where: shows)
    }

    // MARK: Scopes

    /// Finds one side's scopes (DIFF-03), unless they are found or being found: a Swift side's from the parse its colour
    /// tier makes, while swift-syntax colours, and any other's from its braces. They land on the main actor at once.
    private func startScopes(_ side: RenderedSide, of file: PublishedFile) {
        guard let key = side == .old ? file.composition.old : file.composition.new, !decorator.isScoped(key) else {
            return
        }
        let diff = file.diff
        let text = side == .old ? diff.oldText : diff.newText
        let lines = side == .old ? diff.model.oldLines : diff.model.newLines
        let lineRanges = DiffRenderer.lineRanges(of: text, lines: lines)
        let revision = Self.revision(of: key, path: diff.title, language: diff.language)
        let store = decorator.refinesSwiftColor ? decorator.store : nil
        let stamp = DiffDecorator.Stamp(generation: generation, fileID: file.rendered.id)
        decorator.trackScopes(
            taskProvider.task(priority: .utility) {
                let scopes = await DiffDecorations.scopes(
                    of: text, lineRanges: lineRanges, language: diff.language, revision: revision, store: store)
                if let scopes { self.land(scopes, key: key, stamp: stamp) }
                self.decorator.endScopes(key, cancelled: Task.isCancelled)
            }, for: key)
    }

    /// Takes a side's scopes, unless their job was cancelled, or their render was superseded and no published file
    /// shows their content any more; then decorates every published text that shows it.
    private func land(_ scopes: ScopeLines, key: DiffDecorator.ContentKey, stamp: DiffDecorator.Stamp) {
        let files = publishedFiles()
        let shows = { (file: PublishedFile) in file.composition.old == key || file.composition.new == key }
        guard !Task.isCancelled, stamp.generation == generation || files.contains(where: shows) else { return }
        decorator.land(scopes, for: key)
        decorator.publish(files.map { ($0.rendered, $0.composition) })
        sendDecorated(.scopes, where: shows)
    }

    /// The revision a side's job reads: its file's path, its language and its content's key.
    private static func revision(of key: DiffDecorator.ContentKey, path: String, language: Language) -> SourceRevision {
        switch key {
            case .blob(let blob, _): SourceRevision(documentID: path, language: language, key: .content(blob))
            case .preparation(let id, let side):
                SourceRevision(documentID: path, language: language, key: .content("\(id.uuidString)/\(side)"))
        }
    }

    // MARK: Viewport

    /// The source lines of `side` a pane of `file` shows, from the rows it reports (perf11-viewport); nil when no pane
    /// reports any.
    func visibleLines(of side: RenderedSide, in file: PublishedFile) -> Range<Int>? {
        for text in [file.rendered.unified, file.rendered.old, file.rendered.new].compactMap(\.self) {
            guard let rows = decorator.viewport.visibleRows(of: text.id)?.clamped(to: text.rows.indices) else {
                continue
            }
            let numbers = text.rows[rows].compactMap { side == .old ? $0.oldNumber : $0.newNumber }
            if let low = numbers.min(), let high = numbers.max() { return (low - 1) ..< high }
        }
        return nil
    }

    /// The lines of `side` a pane most likely shows first when none reports its rows: those around the file's first
    /// change, where a file opens by default, or its top when it has none.
    static func linesAroundFirstChange(of side: RenderedSide, in diff: PreparedDiff) -> Range<Int> {
        let change = diff.model.structure.changes.first
        let first = (side == .old ? change?.old.lowerBound : change?.new.lowerBound) ?? 0
        let start = max(first - Self.linesAboveChange, 0)
        return start ..< start + Self.visibleLineCount
    }

    /// How many lines a stage decorates first when no pane reports its rows, and how many of them lie above the first
    /// change.
    private static let visibleLineCount = 80
    private static let linesAboveChange = 20
}
