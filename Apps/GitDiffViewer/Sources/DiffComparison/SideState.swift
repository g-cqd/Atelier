package import AemiCore
package import AtelierFileTree
import DiffCore
package import DiffGit
import DiffRendering
package import Foundation
import Observation

/// One comparison target: what it points at, and the files it contains.
@Observable
@MainActor
package final class SideState {
    package enum RefChoice: Hashable {
        case workingTree
        case ref(String)
    }

    package let label: String
    private let reader: any SourceReading
    private let taskProvider: any TaskProvider
    package private(set) var source: ComparisonSource?
    package private(set) var repository: RepositoryInfo?
    package private(set) var entries: [SourceEntry] = []
    /// Files git ignores in a working tree, read on demand by `loadIgnoredEntries()`; nil until then. A reload after
    /// an outside write keeps them (``reloadAfterOutsideWrite()``).
    package private(set) var ignoredEntries: [SourceEntry]?
    package private(set) var entriesByPath: [String: SourceEntry] = [:]
    package private(set) var tree: [PathNode] = []
    package private(set) var isLoading = false
    package private(set) var errorMessage: String?
    package var customRef = ""

    /// The commit this side's ref named when its entries were listed, resolved just before the listing; nil for any
    /// other source, and until a load that resolved it lands.
    package private(set) var resolvedCommit: String?

    /// Whether a fetch is running on this side right now; guards against a second one starting while it is.
    package private(set) var isFetching = false
    /// The last fetch's failure; cleared when another fetch starts or the repository changes.
    package private(set) var lastFetchError: String?
    /// This repository's remote names, read once so the fetch menu can name the primary one; empty until then.
    package private(set) var remoteNames: [String] = []
    /// Whether ``remoteNames`` were read for this repository, so one without a remote is not asked again whenever a
    /// menu is built.
    @ObservationIgnored private var hasReadRemoteNames = false

    /// Where each file of this folder stands against the index, as git's status last reported it; nil for any other
    /// source, for a folder outside every repository, and until git answers.
    private var gitBadgeStates: BadgeChangeStates? {
        didSet { onBadgeStatesChanged?() }
    }
    /// Where each of this side's paths stands in the comparison, merged by the owner from both sides' states; nil
    /// until the owner merges them.
    private var comparisonBadgeStates: BadgeChangeStates?
    /// Bumped by every read of git's status and by every load that brings its own; a read that lands after a newer
    /// one started is dropped.
    @ObservationIgnored private var badgeStatesGeneration = 0
    @ObservationIgnored private var badgeStatesTask: Task<Void, Never>?

    private var loadTask: Task<Void, Never>?
    private var ignoredTask: Task<Void, Never>?
    /// Why the listing behind ``ignoredEntries`` failed, leaving it empty; kept with the list across a reload that
    /// keeps it, so the side goes on saying why the section is empty.
    @ObservationIgnored private var ignoredEntriesFailure: String?
    private var remoteTask: Task<Void, Never>?
    /// The last ref check ``reloadIfRefMoved()`` queued; the next one waits for it.
    @ObservationIgnored private var refCheckTask: Task<Void, Never>?
    /// Set when an outside write asks for a reload while a load runs, which then runs once that load ends.
    @ObservationIgnored private var isOutsideWriteReloadQueued = false
    /// Called whenever a load starts, so the owner can time the comparison from the source change.
    @ObservationIgnored package var onReload: (@MainActor () -> Void)?
    /// Called whenever the entries change, so the owner can recompute the comparison.
    @ObservationIgnored package var onEntriesChanged: (@MainActor () -> Void)?
    /// Called once the ignored files are known, so the owner can add them to the comparison.
    @ObservationIgnored package var onIgnoredEntriesChanged: (@MainActor () -> Void)?
    /// Called after a successful fetch and its ``refreshRepositoryInfo()``, unless this side has since moved to
    /// another repository.
    @ObservationIgnored package var onFetched: (@MainActor () -> Void)?
    /// Called whenever git's answer behind ``badgeStates`` changes, so the owner can update what it derives from it.
    @ObservationIgnored package var onBadgeStatesChanged: (@MainActor () -> Void)?

    /// The production ``SourceLoader``'s process runner, shared for fetches; nil for any other reader, which
    /// disables fetching.
    private var fetchRunner: (any ProcessRunner)? { (reader as? SourceLoader)?.runner }

    package init(label: String, reader: any SourceReading, taskProvider: any TaskProvider) {
        self.label = label
        self.reader = reader
        self.taskProvider = taskProvider
    }

    /// Where every path of this side stands against the index: git's own answer for a folder inside a repository.
    /// Until git answers, and for a folder outside every repository, every path is unstaged, the way a working copy
    /// looks; a ref, a file or a patch is staged throughout. The owner merges both sides' states into what each
    /// explorer draws, ``explorerBadgeStates``.
    package var badgeStates: BadgeChangeStates {
        if let gitBadgeStates { return gitBadgeStates }
        if case .directory = source { return .uniform(.unstaged) }
        return .uniform(.staged)
    }

    /// Where `path`, a file or a folder of this side, stands against the index; see ``badgeStates``.
    package func badgeState(of path: String) -> BadgeChangeState {
        badgeStates.state(of: path)
    }

    /// What this side's explorer draws, keyed by this side's own paths: a change's state in the comparison, which the
    /// owner merges from both sides' ``badgeStates`` so the same file draws the same state in both explorers
    /// (CARD-11). In `HEAD` against the working tree, an edit the index does not hold yet draws stroked on the `HEAD`
    /// side too. This side's own states until the owner merges.
    package var explorerBadgeStates: BadgeChangeStates {
        comparisonBadgeStates ?? badgeStates
    }

    /// Takes the comparison's badge states keyed by this side's paths; see ``explorerBadgeStates``.
    package func showComparisonBadgeStates(_ states: BadgeChangeStates) {
        comparisonBadgeStates = states
    }

    package var refChoice: RefChoice {
        get {
            if case .gitRef(_, let ref) = source { .ref(ref) } else { .workingTree }
        }
        set {
            guard let repository else { return }
            switch newValue {
                case .workingTree: load(.directory(repository.root), repository: repository)
                case .ref(let ref): load(.gitRef(repository: repository.root, ref: ref), repository: repository)
            }
        }
    }

    package func choose(_ url: URL) {
        beginLoading()
        loadTask = taskProvider.task {
            let repository = await reader.repositoryInfo(containing: url)
            guard !Task.isCancelled else { return }
            let source: ComparisonSource = url.hasDirectoryPath ? .directory(url) : .file(url)
            load(source, repository: repository)
        }
    }

    package func selectCustomRef() {
        let ref = customRef.trimmingCharacters(in: .whitespaces)
        guard let repository, !ref.isEmpty else { return }
        beginLoading()
        loadTask = taskProvider.task {
            do {
                let resolved = try await reader.resolve(ref: ref, in: repository.root)
                guard !Task.isCancelled else { return }
                load(.gitRef(repository: repository.root, ref: resolved), repository: repository)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = "Unknown ref \(ref)"
                isLoading = false
                runQueuedOutsideWriteReload()
            }
        }
    }

    package func load(_ source: ComparisonSource, repository: RepositoryInfo?) {
        let isNewSource = source != self.source
        self.source = source
        setRepository(repository)
        // Another tree's states would badge this one's files until its own status lands.
        if isNewSource { gitBadgeStates = nil }
        reload()
    }

    /// Takes a repository without choosing anything in it yet, so the menu offers its branches and the
    /// comparison waits for that choice.
    package func adopt(repository: RepositoryInfo) {
        guard source == nil else { return }
        setRepository(repository)
    }

    /// Assigns ``repository``; a new root clears the previous repository's remote names and fetch error.
    private func setRepository(_ repository: RepositoryInfo?) {
        if repository?.root != self.repository?.root {
            remoteTask?.cancel()
            remoteTask = nil
            remoteNames = []
            hasReadRemoteNames = false
            lastFetchError = nil
        }
        self.repository = repository
    }

    /// Marks the side as loading while the owner reads it; `load(_:repository:entries:)` or `endLoading()` ends it.
    package func beginLoading() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
    }

    package func endLoading() {
        isLoading = false
        runQueuedOutsideWriteReload()
    }

    /// Adopts entries the owner already read, with the badge states it read beside them (nil when it read none) and,
    /// for a ref, the commit it resolved before listing them (nil when it did not), so the comparison starts without
    /// another round trip. The owner reports the change itself, so both sides can be swapped in before anything is
    /// recomputed.
    package func load(
        _ source: ComparisonSource, repository: RepositoryInfo?, entries: [SourceEntry], ignored: [SourceEntry]? = nil,
        badgeStates: BadgeChangeStates? = nil, resolvedCommit: String? = nil
    ) {
        loadTask?.cancel()
        self.source = source
        setRepository(repository)
        isLoading = false
        errorMessage = nil
        self.resolvedCommit = resolvedCommit
        publish(badgeStates, generation: beginBadgeStatesRead())
        forgetIgnoredEntries()
        ignoredEntries = ignored
        apply(entries, notifying: false)
        runQueuedOutsideWriteReload()
    }

    /// Re-reads this side's repository info (branches, tags, commits) without touching its entries; a no-op without
    /// a repository. The result is dropped if this side moved to another repository meanwhile.
    /// - Returns: The info read, or nil when none was, so a caller can hand it to a side of the same repository.
    @discardableResult
    package func refreshRepositoryInfo() async -> RepositoryInfo? {
        guard let repository else { return nil }
        let root = repository.root
        guard let refreshed = await reader.repositoryInfo(containing: root) else { return nil }
        guard self.repository?.root == root else { return nil }
        self.repository = refreshed
        return refreshed
    }

    /// Takes repository info the other side just read, sparing a second read of the same refs; ignored when it
    /// describes another repository than this side's.
    package func updateRepositoryInfo(_ info: RepositoryInfo) {
        guard repository?.root == info.root else { return }
        repository = info
    }

    /// Reads this repository's remote names once, none included; a no-op once they are known, without a repository,
    /// or without a runner. A failed read is tried again at the next call.
    package func loadRemotesIfNeeded() {
        guard !hasReadRemoteNames, remoteTask == nil, let repository, let runner = fetchRunner else { return }
        let root = repository.root
        remoteTask = taskProvider.task {
            let remotes = try? await GitClient(repository: root, runner: runner).remotes()
            remoteTask = nil
            guard self.repository?.root == root, let remotes else { return }
            remoteNames = remotes.map(\.name)
            hasReadRemoteNames = true
        }
    }

    /// Fetches from the primary remote (`origin` when none is known), then refreshes the repository info; a failure
    /// lands in ``lastFetchError``. A call while a fetch runs does nothing, and nothing is published once this side
    /// has moved to another repository.
    package func fetch() async {
        guard !isFetching, let repository, let runner = fetchRunner else { return }
        let root = repository.root
        isFetching = true
        lastFetchError = nil
        defer { isFetching = false }
        if remoteNames.isEmpty {
            let remotes = (try? await GitClient(repository: root, runner: runner).remotes().map(\.name)) ?? []
            // The side may have moved to another repository while `remotes()` ran.
            guard self.repository?.root == root else { return }
            remoteNames = remotes
        }
        let remote = remoteNames.first ?? "origin"
        do {
            try await GitClient(repository: root, runner: runner).fetch(remote: remote)
        } catch {
            guard self.repository?.root == root else { return }
            lastFetchError = error.localizedDescription
            return
        }
        guard self.repository?.root == root else { return }
        await refreshRepositoryInfo()
        onFetched?()
    }

    /// Reads this side's files again, with git's status beside them for a folder and, for a ref, the commit it names
    /// resolved first. A load already running is superseded, and the ignored files are listed anew.
    package func reload() {
        startReload(keepingIgnoredEntries: false)
    }

    private func startReload(keepingIgnoredEntries: Bool) {
        guard let source else { return }
        // This listing starts after every write asked about so far.
        isOutsideWriteReloadQueued = false
        loadTask?.cancel()
        isLoading = true
        errorMessage = keepingIgnoredEntries ? ignoredEntriesFailure : nil
        onReload?()
        let generation = beginBadgeStatesRead()
        let reader = reader
        loadTask = taskProvider.task {
            // Git's status runs beside the listing, so the files and their badges land together.
            async let badgeStates = Self.readBadgeStates(of: source, reader: reader)
            do {
                let listing = try await Self.listing(of: source, reader: reader)
                let states = await badgeStates
                guard !Task.isCancelled else { return }
                isLoading = false
                resolvedCommit = listing.commit
                publish(states, generation: generation)
                if !keepingIgnoredEntries { forgetIgnoredEntries() }
                apply(listing.entries, notifying: true)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                resolvedCommit = nil
                forgetIgnoredEntries()
                apply([], notifying: true)
            }
            runQueuedOutsideWriteReload()
        }
    }

    /// Re-reads git's status for this side's folder and swaps in the badge states it gives, without re-reading the
    /// files: staging or committing moves what the index holds, not what the files hold. A no-op for any other
    /// source; a later read or load supersedes it.
    package func refreshBadgeStates() {
        guard let source, case .directory = source else { return }
        let generation = beginBadgeStatesRead()
        let reader = reader
        badgeStatesTask = taskProvider.task {
            let states = await Self.readBadgeStates(of: source, reader: reader)
            guard !Task.isCancelled else { return }
            publish(states, generation: generation)
        }
    }

    /// Git's status for `source` as badge states, read and built off the main actor: nil when `source` is not a
    /// folder inside a repository, and when git fails, which leaves the side its look without git.
    @concurrent
    nonisolated static func readBadgeStates(of source: ComparisonSource, reader: any SourceReading) async
        -> BadgeChangeStates?
    {
        do {
            return try await reader.workingTreeStatus(of: source).map(BadgeChangeStates.init(status:))
        } catch is CancellationError {
            return nil
        } catch {
            PhaseTrace.log("git status failed for \(source.displayName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Supersedes every earlier read of git's status; returns the generation a new result must still hold to land.
    private func beginBadgeStatesRead() -> Int {
        badgeStatesTask?.cancel()
        badgeStatesTask = nil
        badgeStatesGeneration += 1
        return badgeStatesGeneration
    }

    private func publish(_ states: BadgeChangeStates?, generation: Int) {
        guard generation == badgeStatesGeneration else { return }
        gitBadgeStates = states
    }

    /// Reads the files git ignores, once per source and only when asked: the listing takes seconds on a tree full
    /// of build output, so the comparison never waits for it. A failed listing leaves the list empty and says why on
    /// this side's error line (GDV S13), since an empty section alone reads as "nothing ignored".
    package func loadIgnoredEntries() {
        guard let source, ignoredEntries == nil, ignoredTask == nil else { return }
        let reader = reader
        ignoredTask = taskProvider.task {
            let listed: [SourceEntry]
            var failure: String?
            do {
                listed = try await reader.ignoredEntries(of: source)
            } catch is CancellationError {
                return
            } catch {
                listed = []
                failure = "Ignored files: \(error.localizedDescription)"
            }
            guard !Task.isCancelled else { return }
            ignoredEntries = listed
            ignoredEntriesFailure = failure
            if let failure { errorMessage = failure }
            ignoredTask = nil
            onIgnoredEntriesChanged?()
        }
    }

    /// Drops the ignored files and any listing of them still running, for a source or a reload that lists them anew.
    private func forgetIgnoredEntries() {
        ignoredTask?.cancel()
        ignoredTask = nil
        ignoredEntries = nil
        ignoredEntriesFailure = nil
    }

    private func apply(_ entries: [SourceEntry], notifying: Bool) {
        self.entries = entries
        entriesByPath = Dictionary(entries.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        tree = PathNode.tree(from: entries.map(\.relativePath))
        if notifying { onEntriesChanged?() }
    }
}

/// What an outside change makes a side read again: its files after a write that can change what it lists (GDV S2),
/// without cutting a running listing short, and its ref when the commit it names moved (GDV S3).
extension SideState {
    /// The watcher's reload after an outside write. The ignored files already listed stay (GDV S13): a write seldom
    /// changes what git ignores, and listing it again takes seconds in a tree full of build output. A load already
    /// running is left to land and this reload follows it, rather than cancelling it, so writes that arrive faster
    /// than a listing takes cannot keep every listing from landing.
    package func reloadAfterOutsideWrite() {
        guard !isLoading else {
            isOutsideWriteReloadQueued = true
            return
        }
        startReload(keepingIgnoredEntries: true)
    }

    /// Runs the reload an outside write asked for while the load that just ended ran.
    private func runQueuedOutsideWriteReload() {
        guard isOutsideWriteReloadQueued else { return }
        isOutsideWriteReloadQueued = false
        startReload(keepingIgnoredEntries: true)
    }

    /// Reloads when this side's ref now names another commit than the one its entries were listed at (GDV S3); a
    /// no-op for any other source, and a reload when the commit is unknown or the ref no longer resolves. Checks run
    /// one after another, each after the load then in flight, so two notices of one move, the refs watcher's and a
    /// fetch's, reload once, and a check never reloads again what a running load already picks up.
    package func reloadIfRefMoved() {
        guard case .gitRef = source else { return }
        let previous = refCheckTask
        refCheckTask = taskProvider.task {
            await previous?.value
            await reloadUnlessCurrent()
        }
    }

    private func reloadUnlessCurrent() async {
        // A load that starts while another is awaited, the one a custom ref chains or a new choice, lists afresh:
        // its commit is the one to compare with, so the check waits for loads to stop starting.
        var awaited: Task<Void, Never>?
        while let running = loadTask, running != awaited {
            awaited = running
            await running.value
        }
        guard case .gitRef(let repository, let ref) = source else { return }
        let listedAt = resolvedCommit
        let current: String?
        do {
            current = try await reader.resolve(ref: ref, in: repository)
        } catch is CancellationError {
            return
        } catch {
            // The ref is gone, or git fails: the reload says so where this side's errors show.
            current = nil
        }
        guard !Task.isCancelled, source == .gitRef(repository: repository, ref: ref) else { return }
        if current == nil || current != listedAt {
            reload()
        }
    }

    /// Whether writes at `paths`, relative to this folder, can change what a reload lists (GDV S2), sorted by
    /// ``WorkingTreeWrites``: a listed file or folder can, and so can a new path git does not ignore, which one
    /// `git check-ignore` judges for every unlisted path at once. When git cannot judge, the writes count, so no edit
    /// is missed for a failed check.
    package func listingMayChange(at paths: Set<String>) async -> Bool {
        guard let source else { return false }
        let writes = WorkingTreeWrites(paths) { lists($0) }
        if writes.touchesListing { return true }
        guard !writes.unlisted.isEmpty else { return false }
        do {
            let ignored = try await reader.ignoredPaths(among: writes.unlisted, in: source)
            return writes.unlisted.contains { !ignored.contains($0) }
        } catch is CancellationError {
            return false
        } catch {
            PhaseTrace.log("git check-ignore failed for \(source.displayName): \(error.localizedDescription)")
            return true
        }
    }

    /// Whether `path` names a listed file, or a folder holding listed files, which ``tree`` has a node for.
    /// - Complexity: O(depth × siblings) for a path that is not a listed file.
    private func lists(_ path: String) -> Bool {
        if entriesByPath[path] != nil { return true }
        let components = path.split(separator: "/")
        guard !components.isEmpty else { return false }
        var level = tree
        for component in components {
            guard let node = level.first(where: { $0.name == component }) else { return false }
            level = node.children ?? []
        }
        return true
    }

    /// A side's files as one read lists them.
    package struct Listing: Sendable {
        package let entries: [SourceEntry]
        /// The commit a ref named just before its tree was listed; nil for any other source, and when git could not
        /// resolve the ref, which the listing then reports.
        package let commit: String?
    }

    /// Lists `source`, resolving a ref first: a ref that moves in between then reads as moved at the next check
    /// (``reloadIfRefMoved()``), never as current.
    nonisolated static func listing(of source: ComparisonSource, reader: any SourceReading) async throws -> Listing {
        var commit: String?
        if case .gitRef(let repository, let ref) = source {
            do {
                commit = try await reader.resolve(ref: ref, in: repository)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                PhaseTrace.log("git rev-parse failed for \(source.displayName): \(error.localizedDescription)")
            }
        }
        return Listing(entries: try await reader.entries(of: source), commit: commit)
    }
}
