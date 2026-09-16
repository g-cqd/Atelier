package import AemiCore
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
    package private(set) var tree: [FileNode] = []
    package private(set) var isLoading = false
    package private(set) var errorMessage: String?
    package var customRef = ""

    private var loadTask: Task<Void, Never>?
    private var ignoredTask: Task<Void, Never>?
    /// Called whenever a load starts, so the owner can time the comparison from the source change.
    @ObservationIgnored package var onReload: (@MainActor () -> Void)?
    /// Called whenever the entries change, so the owner can recompute the comparison.
    @ObservationIgnored package var onEntriesChanged: (@MainActor () -> Void)?
    /// Called once the ignored files are known, so the owner can add them to the comparison.
    @ObservationIgnored package var onIgnoredEntriesChanged: (@MainActor () -> Void)?

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
        self.repository = repository
        reload()
    }

    /// Takes a repository without choosing anything in it yet, so the menu offers its branches and the
    /// comparison waits for that choice.
    package func adopt(repository: RepositoryInfo) {
        guard source == nil else { return }
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
        self.repository = repository
        isLoading = false
        errorMessage = nil
        apply(entries, ignored: ignored, notifying: false)
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
        tree = FileNode.tree(from: entries.map(\.relativePath))
        if notifying { onEntriesChanged?() }
    }
}
