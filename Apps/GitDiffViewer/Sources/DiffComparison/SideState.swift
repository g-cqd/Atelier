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
    /// The last fetch's failure; cleared when another fetch starts or the repository changes.
    package private(set) var lastFetchError: String?
    /// This repository's remote names, read once so the fetch menu can name the primary one; empty until then.
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
    /// Called after a successful fetch and its ``refreshRepositoryInfo()``, unless this side has since moved to
    /// another repository.
    @ObservationIgnored package var onFetched: (@MainActor () -> Void)?

    /// The production ``SourceLoader``'s process runner, shared for fetches; nil for any other reader, which
    /// disables fetching.
    private var fetchRunner: (any ProcessRunner)? { (reader as? SourceLoader)?.runner }

    package init(label: String, reader: any SourceReading, taskProvider: any TaskProvider) {
        self.label = label
        self.reader = reader
        self.taskProvider = taskProvider
    }

    /// Where this side's changes stand against the index, for its file badges: ``BadgeChangeState/unstaged`` for a
    /// directory source, ``BadgeChangeState/staged`` for anything else.
    package var badgeState: BadgeChangeState {
        if case .directory = source { .unstaged } else { .staged }
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

    /// Assigns ``repository``; a new root clears the previous repository's remote names and fetch error.
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

    /// Re-reads this side's repository info (branches, tags, commits) without touching its entries; a no-op without
    /// a repository. The result is dropped if this side moved to another repository meanwhile.
    package func refreshRepositoryInfo() async {
        guard let repository else { return }
        let root = repository.root
        guard let refreshed = await reader.repositoryInfo(containing: root) else { return }
        guard self.repository?.root == root else { return }
        self.repository = refreshed
    }

    /// Reads this repository's remote names once; a no-op once they are known, without a repository, or without a
    /// runner.
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
