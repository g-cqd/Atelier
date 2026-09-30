package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
import Foundation
import Observation

/// Turns the selection into what the detail area shows: one document for a file, one card per file for a folder.
///
/// A render either starts from nothing, publishing the first file as soon as it lands and the rest behind it, or keeps
/// what is published on screen until the whole replacement lands in one step. Every render carries its generation, so
/// a superseded one never overwrites a newer one. What is published stays interactive meanwhile, gap drags and
/// relayouts included: each published file keeps the stamp it was rendered under, and work that lands under a stamp
/// that moved on is rendered again rather than shown out of date.
@MainActor
@Observable
package final class RenderPipeline {
    package enum Event {
        /// A render reached the model; `isFirst` for the file or the first card of a generation.
        case published(RenderedDiff.ID, isFirst: Bool)
        /// A stage after the text landed on a published file a pane shows (PERF-09), always after the file's
        /// `.published`; it may come after `.finished`, which says the render published everything.
        case decorated(RenderedDiff.ID, DecorationLayer)
        case finished
        case failed(String)
    }

    /// The two sources a render compares.
    package struct Sources: Equatable, Sendable {
        package let left: ComparisonSource
        package let right: ComparisonSource
    }

    /// The sources and diff options of one render.
    struct RenderInputs {
        let sources: Sources
        let granularity: IntralineGranularity
        let heuristics: DiffHeuristics
    }

    /// What a published file was rendered under: the rendering configuration, whether it shows changes only, and its
    /// own gap expansions by gap index. A file whose stamp is no longer the current one shows something stale.
    struct Stamp: Equatable {
        let configuration: Int
        let showsChangesOnly: Bool
        let expansions: [Int: GapExpansion]
        /// The changes the compact inline view shows disclosed, by change index (book DIFF-04).
        let disclosed: Set<Int>
        /// The file's folded scopes, each with its last line (DIFF-03).
        let folds: [ScopeFoldKey: Int]
    }

    /// A rendered file with the stamp it was rendered under.
    typealias Stamped = (file: RenderedDiff, stamp: Stamp)

    package internal(set) var file: RenderedDiff?
    package internal(set) var cards: [RenderedFile] = []
    /// The target of what is published; `prepared` holds its diffs, one per pair that landed, in order.
    package internal(set) var target: Target?
    /// Bumped each time ``target`` is set, so what is derived from its pairs is kept until the next one.
    @ObservationIgnored package internal(set) var targetVersion = 0
    /// The sources `file` or `cards` were rendered from, set in the same step as they are; nil while neither shows
    /// anything. The model compares them with the sides' own to tell a previous comparison kept on screen.
    package internal(set) var publishedSources: Sources?
    /// Rows revealed around the gaps of what is published, keyed per file and gap.
    package internal(set) var gapExpansions: [GapKey: GapExpansion] = [:]
    /// The changes of what is published that the compact inline view shows disclosed (book DIFF-04).
    package internal(set) var disclosedChanges: Set<ChangeKey> = []
    /// The folded scopes of what is published, each with its last line on its side (DIFF-03).
    package internal(set) var foldedScopes: [ScopeFoldKey: Int] = [:]
    /// Folds carried through a reload whose side's content may have changed: not drawn until that side's new scopes
    /// land and show which of them still fold a scope (DIFF-03).
    package internal(set) var pendingFolds: [ScopeFoldKey: Int] = [:]
    package internal(set) var error: String?
    /// Diffs of what is published, kept so layout changes and gap drags re-render without reloading or re-diffing.
    @ObservationIgnored package internal(set) var prepared: [PreparedDiff] = []
    @ObservationIgnored package var onEvent: ((Event) -> Void)?
    /// The stamp each published file was rendered under, parallel to `prepared`.
    @ObservationIgnored var stamps: [Stamp] = []

    /// Bumped by every render; work from an older generation is dropped when it lands.
    @ObservationIgnored var generation = 0
    @ObservationIgnored var completedGeneration = 0
    /// Whether a render is in flight: `completedGeneration < generation`, mirrored into an observed store so an
    /// observer sees both edges, since `generation` is bumped inside update passes and cannot be observed itself.
    /// It stays true until the replacement of what is kept on screen has landed, so kept content never reads as final.
    package internal(set) var isRendering = false
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var options: DiffRenderer.Options
    @ObservationIgnored var layout: (context: Int, isolates: Bool) = (3, false)
    /// Bumped whenever `configure` changes how diffs render, which leaves every stamp before it stale.
    @ObservationIgnored var configuration = 0
    /// Bumped whenever what is published is replaced or taken away, not when it is rendered again or extended; a
    /// relayout lands only on the content it rendered.
    @ObservationIgnored var contentVersion = 0
    @ObservationIgnored var relayoutTask: Task<Void, Never>?
    /// Bumped by every relayout; one that lands after a newer one started is dropped.
    @ObservationIgnored var relayoutGeneration = 0

    /// Granularity and heuristics of what is published; a render borrows published work only when they match.
    @ObservationIgnored var publishedGranularity: IntralineGranularity?
    @ObservationIgnored var publishedHeuristics: DiffHeuristics?
    /// The card lists taken off screen, the latest last, kept so going back to one lends its cards again rather than
    /// rendering them all anew (book PERF-10): the whole list after a file or a folder's list showed in its place, from
    /// a closed tab or from the file list's fixed tab (book TAB-10). A render of a list takes the one with its files.
    @ObservationIgnored var shelvedLists: [ShelvedList] = []

    /// How many card lists stay shelved: the whole list and a few folders' lists. The oldest goes first.
    package static let shelfCapacity = 3

    let preparer: DiffPreparer
    let taskProvider: any TaskProvider
    let renderer: PaneRenderer
    /// The stages after the text: each displayed file's colour, emphasis and moved lines (PERF-09); see
    /// `RenderPipeline+Decoration.swift`.
    let decorator: DiffDecorator

    package init(
        preparer: DiffPreparer, taskProvider: any TaskProvider, options: DiffRenderer.Options,
        renderer: PaneRenderer = .live, decorator: DiffDecorator = DiffDecorator()
    ) {
        self.preparer = preparer
        self.taskProvider = taskProvider
        self.options = options
        self.renderer = renderer
        self.decorator = decorator
    }

    /// Options for the next renders. A change to how diffs render leaves what is published stale until `relayout`
    /// renders it again; a render in flight picks the change up by itself.
    package func configure(options: DiffRenderer.Options, context: Int, isolatesChanges: Bool) {
        if !Self.rendersAlike(options, self.options) || context != layout.context || isolatesChanges != layout.isolates
        {
            configuration += 1
        }
        self.options = options
        layout = (context, isolatesChanges)
    }

    package func clear() {
        task?.cancel()
        decorator.cancel(keepingColors: [], marks: [])
        shelvedLists = []
        generation += 1
        completedGeneration = generation
        isRendering = false
        unpublish()
        target = nil
        targetVersion &+= 1
        error = nil
    }

    /// Renders `target`. With `keepingPublished`, what is on screen stays there, and interactive, until the whole of
    /// `target` replaces it in one step; otherwise it goes at once and `target` streams in, first file first. Either
    /// way a pair with the same path, blobs and diff options as a published one borrows its prepared diff, and its
    /// rendered file when it keeps its place under a current stamp, so the views keyed on it never rebuild.
    package func render(
        _ target: Target, left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity,
        heuristics: DiffHeuristics, keepingPublished: Bool
    ) {
        task?.cancel()
        preparer.cancelPrefetch()
        generation += 1
        isRendering = true
        error = nil
        let inputs = RenderInputs(
            sources: Sources(left: left, right: right), granularity: granularity, heuristics: heuristics)
        holdFolds(forContentOf: target)
        let loan = self.loan(for: target, inputs: inputs)
        let keeps = keepingPublished && (file != nil || !cards.isEmpty)
        if target.isCards { shelvedLists.removeAll { $0.target.showsSameFiles(as: target) } }
        if !keeps, let published = self.target, published.isCards, !published.showsSameFiles(as: target),
            !prepared.isEmpty
        {
            shelve(published)
        }
        // A lent file drawn another way, a card becoming the whole file say, saves only its diff: streaming then puts
        // the first file on screen sooner than one step would.
        let lendsFiles = loan.rendered.contains { $0.value.stamp == currentStamp(forIndex: $0.key, in: target) }
        if !keeps {
            gapExpansions = carriedExpansions(into: target)
            disclosedChanges = carriedDisclosures(into: target)
            unpublish()
            self.target = target
            targetVersion &+= 1
            publishedGranularity = granularity
            publishedHeuristics = heuristics
        }
        let job = RenderJob(
            target: target, inputs: inputs, generation: generation, keepingScroll: loan.sameFilePath,
            loan: keeps ? nil : loan)
        if keeps || lendsFiles {
            renderWhole(job)
        } else {
            stream(job)
        }
    }

    /// Renders everything published again, off the main actor, with the current configuration; without
    /// `keepingScroll`, every gap folds back too. A render in flight renders its own files again when it lands.
    package func relayout(keepingScroll: Bool) {
        if !keepingScroll {
            gapExpansions = [:]
            disclosedChanges = []
            foldedScopes = [:]
            pendingFolds = [:]
        }
        refresh(keepingScroll: keepingScroll)
    }
}
