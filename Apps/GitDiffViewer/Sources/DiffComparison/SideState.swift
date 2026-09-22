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
    /// Files git ignores in a working tree, read on demand by `loadIgnoredEntries()`; nil until then.
    package private(set) var ignoredEntries: [SourceEntry]?
    package private(set) var entriesByPath: [String: SourceEntry] = [:]
    package private(set) var tree: [PathNode] = []
    package private(set) var isLoading = false
    package private(set) var errorMessage: String?
    package var customRef = ""

    /// Whether a fetch is running on this side right now; guards against a second one starting while it is.
    package private(set) var isFetching = false
    /// The last fetch's failure, cleared as soon as another fetch starts or one succeeds; nil when the last fetch
    /// (or none yet) did not fail.
    package private(set) var lastFetchError: String?
    /// This repository's remote names, read once (`git remote -v`) so the fetch menu can name the primary one
    /// instead of assuming "origin"; empty until ``loadRemotesIfNeeded()`` runs, or when the repository has none.
    package private(set) var remoteNames: [String] = []

    private var loadTask: Task<Void, Never>?
    private var ignoredTask: Task<Void, Never>?
    private var remoteTask: Task<Void, Never>?
    /// Called whenever a load starts, so the owner can time the comparison from the source change.
    @ObservationIgnored package var onReload: (@MainActor () -> Void)?
    /// Called whenever the entries change, so the owner can recompute the comparison.
    @ObservationIgnored package var onEntriesChanged: (@MainActor () -> Void)?
    /// Called once the ignored files are known, so the owner can add them to the comparison.
    @ObservationIgnored package var onIgnoredEntriesChanged: (@MainActor () -> Void)?
    /// Called once a fetch this side ran succeeds and ``refreshRepositoryInfo()`` has already run for it, so the
    /// owner can refresh whatever else shares this repository and re-run a comparison a moved remote-tracking ref
    /// changed. Never called for a fetch whose repository this side has since moved away from.
    @ObservationIgnored package var onFetched: (@MainActor () -> Void)?

    /// How git is spawned for a fetch, reused from the app's own reader when it is the production
    /// ``SourceLoader`` -- the same width-4 pool every other git command on this side already runs on. A reader
    /// that isn't one, every test double included, simply has no runner to share, so fetching is unavailable.
    private var fetchRunner: (any ProcessRunner)? { (reader as? SourceLoader)?.runner }

    package init(label: String, reader: any SourceReading, taskProvider: any TaskProvider) {
        self.label = label
        self.reader = reader
        self.taskProvider = taskProvider
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
            }
        }
    }

    package func load(_ source: ComparisonSource, repository: RepositoryInfo?) {
        self.source = source
        setRepository(repository)
        reload()
    }

    /// Takes a repository without choosing anything in it yet, so the menu offers its branches and the
    /// comparison waits for that choice.
    package func adopt(repository: RepositoryInfo) {
        guard source == nil else { return }
        setRepository(repository)
    }

    /// Assigns ``repository``, clearing whatever this side read about a previous repository's fetch (its remote
    /// names, its last failure) when the root actually changes; a refresh of the same repository keeps them.
    private func setRepository(_ repository: RepositoryInfo?) {
        if repository?.root != self.repository?.root {
            remoteTask?.cancel()
            remoteTask = nil
            remoteNames = []
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
    }

    /// Adopts entries the owner already read, so the comparison starts without another round trip. The owner
    /// reports the change itself, so both sides can be swapped in before anything is recomputed.
    package func load(
        _ source: ComparisonSource, repository: RepositoryInfo?, entries: [SourceEntry], ignored: [SourceEntry]? = nil
    ) {
        loadTask?.cancel()
        self.source = source
        setRepository(repository)
        isLoading = false
        errorMessage = nil
        apply(entries, ignored: ignored, notifying: false)
    }

    /// Re-reads this side's repository info (branches, tags, commits) without touching its entries, so a fetch or
    /// a ref/`.git/refs` change updates whatever reads ``repository`` (the branch/tag menus) without a full
    /// reload. A no-op before any source is chosen, since there is nothing to re-read against yet.
    ///
    /// Guarded the same way ``fetch()`` guards its own publication: this side may have moved on to another
    /// repository entirely while the read was in flight, and publishing what was just read for the old one over
    /// the new one's already-published info would make the branch/tag menu and a subsequent fetch target the
    /// wrong repository.
    package func refreshRepositoryInfo() async {
        guard let repository else { return }
        let root = repository.root
        guard let refreshed = await reader.repositoryInfo(containing: root) else { return }
        guard self.repository?.root == root else { return }
        self.repository = refreshed
    }

    /// Reads this repository's remotes once, so the fetch menu can name the primary one instead of assuming
    /// "origin"; called when the fetch menu item is about to be shown. A no-op once names are known, before a
    /// repository, or without a runner to read them with.
    package func loadRemotesIfNeeded() {
        guard remoteNames.isEmpty, remoteTask == nil, let repository, let runner = fetchRunner else { return }
        let root = repository.root
        remoteTask = taskProvider.task {
            let remotes = (try? await GitClient(repository: root, runner: runner).remotes()) ?? []
            remoteTask = nil
            guard self.repository?.root == root else { return }
            remoteNames = remotes.map(\.name)
        }
    }

    /// Fetches from this repository's primary remote (`origin` before one is known), then re-reads this side's
    /// repository info so its branch and tag menus see whatever moved. One fetch at a time: a call while one is
    /// already running does nothing. ``onFetched`` only fires once the repository this fetch ran against is still
    /// this side's own -- a comparison that moved on in the meantime hears nothing from it.
    package func fetch() async {
        guard !isFetching, let repository, let runner = fetchRunner else { return }
        let root = repository.root
        isFetching = true
        lastFetchError = nil
        defer { isFetching = false }
        if remoteNames.isEmpty {
            let remotes = (try? await GitClient(repository: root, runner: runner).remotes().map(\.name)) ?? []
            // This side may already have moved to another repository while `remotes()` was in flight; publishing
            // this fetch's own repository's remotes over whatever the new one already knows would misname the
            // remote the rest of this fetch, still targeting the old root below, runs against.
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

    package func reload() {
        guard let source else { return }
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        onReload?()
        loadTask = taskProvider.task {
            do {
                let entries = try await reader.entries(of: source)
                guard !Task.isCancelled else { return }
                isLoading = false
                apply(entries, ignored: nil, notifying: true)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                apply([], ignored: nil, notifying: true)
            }
        }
    }

    /// Reads the files git ignores, once per source and only when asked: the listing takes seconds on a tree
    /// full of build output, so the comparison never waits for it.
    package func loadIgnoredEntries() {
        guard let source, ignoredEntries == nil, ignoredTask == nil else { return }
        ignoredTask = taskProvider.task {
            let ignored = (try? await reader.ignoredEntries(of: source)) ?? []
            guard !Task.isCancelled else { return }
            ignoredEntries = ignored
            ignoredTask = nil
            onIgnoredEntriesChanged?()
        }
    }

    private func apply(_ entries: [SourceEntry], ignored: [SourceEntry]?, notifying: Bool) {
        ignoredTask?.cancel()
        ignoredTask = nil
        self.entries = entries
        ignoredEntries = ignored
        entriesByPath = Dictionary(entries.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        tree = PathNode.tree(from: entries.map(\.relativePath))
        if notifying { onEntriesChanged?() }
    }
}
