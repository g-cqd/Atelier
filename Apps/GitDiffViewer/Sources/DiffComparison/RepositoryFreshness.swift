package import AemiCore
package import AtelierFileTree
package import DiffGit
package import Foundation

/// The ``AtelierFileTree/FileWatcher`` API ``RepositoryFreshness`` drives, as a protocol so a test can inject a
/// synthetic source.
package protocol WatchEventSource: Sendable {
    var events: AsyncStream<FileWatcher.FileWatchEvent> { get }
    func watchDirectory(_ path: String) async
    func watchFile(_ path: String) async
    func unwatchFile(_ path: String) async
    func stop() async
}

extension FileWatcher: WatchEventSource {}

/// Watches a working-tree comparison's on-disk files and `.git` metadata for changes made outside the app (a
/// branch switch, a pull, an edit in another editor), and tells its owner when to reload. Each kind of change
/// fires its callback on a trailing debounce, so a git operation touching many files produces one reload.
@MainActor
package final class RepositoryFreshness {
    /// The normalized paths one comparison watches, computed once at attach.
    struct WatchedPaths: Sendable {
        let root: String
        let gitDir: String
        let head: String
        let packedRefs: String
        let refs: String
    }

    /// Where a watched path landed, hence which callback (if any) its event feeds.
    enum Classification: Equatable {
        case tree
        case head
        case refs
        case ignored
    }

    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let treeDebounce: Duration
    private let refDebounce: Duration
    private let makeWatcher: @Sendable () -> any WatchEventSource

    private var watcher: (any WatchEventSource)?
    private var consumerTask: Task<Void, Never>?
    private var treeTask: Task<Void, Never>?
    private var headTask: Task<Void, Never>?
    private var refsTask: Task<Void, Never>?
    /// Bumped by every ``teardown()`` and ``attach(root:)``; events and debounces from an older generation are dropped.
    private var generation = 0

    private var lastRightSource: ComparisonSource?
    private var lastRepositoryRoot: URL?
    package private(set) var isEnabled: Bool

    /// A tree file changed; the owner should reload the right side's entries.
    package var onTreeChanged: (() -> Void)?
    /// `.git/HEAD` changed, so the working tree's diff base may have moved; the owner should compare afresh.
    package var onHeadChanged: (() -> Void)?
    /// A loose or packed ref other than HEAD changed, such as a fetch moving a remote-tracking branch.
    package var onRefsChanged: (() -> Void)?

    /// - Parameters:
    ///   - taskProvider: Spawns the watcher's consumer task and every debounce timer.
    ///   - isEnabled: The initial ``ViewerSettings/autoRefresh``; later changes arrive through ``setEnabled(_:)``.
    ///   - clock: Drives the debounces; tests inject a virtual one.
    ///   - treeDebounce: Trailing coalesce for working-tree events; kept above the diagnostics session's own
    ///     debounce so a refresh never races the analysis it triggers.
    ///   - refDebounce: Trailing coalesce for `HEAD` and ref events, short since they arrive alone.
    ///   - makeWatcher: Builds the ``WatchEventSource`` for each attachment; a test substitutes a synthetic one.
    package init(
        taskProvider: any TaskProvider, isEnabled: Bool, clock: any Clock<Duration> = ContinuousClock(),
        treeDebounce: Duration = .milliseconds(600), refDebounce: Duration = .milliseconds(150),
        makeWatcher: @escaping @Sendable () -> any WatchEventSource = { FileWatcher() }
    ) {
        self.taskProvider = taskProvider
        self.isEnabled = isEnabled
        self.clock = clock
        self.treeDebounce = treeDebounce
        self.refDebounce = refDebounce
        self.makeWatcher = makeWatcher
    }

    deinit {
        consumerTask?.cancel()
        treeTask?.cancel()
        headTask?.cancel()
        refsTask?.cancel()
        // A bare `Task`: `taskProvider.task` would capture `self`, which a deinit cannot do.
        if let watcher {
            Task { await watcher.stop() }
        }
    }

    /// Attaches to the right side when it is the working tree at `repositoryRoot`, and detaches otherwise.
    package func comparisonChanged(rightSource: ComparisonSource?, repositoryRoot: URL?) {
        lastRightSource = rightSource
        lastRepositoryRoot = repositoryRoot
        refreshAttachment()
    }

    /// Mirrors ``ViewerSettings/autoRefresh``: off tears the watcher down, on re-attaches to the last comparison.
    package func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        refreshAttachment()
    }

    /// Stops watching and cancels every pending debounce, keeping the last comparison for a later re-attach.
    package func teardown() {
        generation &+= 1
        consumerTask?.cancel()
        consumerTask = nil
        treeTask?.cancel()
        treeTask = nil
        headTask?.cancel()
        headTask = nil
        refsTask?.cancel()
        refsTask = nil
        guard let watcher else { return }
        self.watcher = nil
        taskProvider.task { await watcher.stop() }
    }

    private func refreshAttachment() {
        teardown()
        guard isEnabled, case .directory(let treeRoot) = lastRightSource, let lastRepositoryRoot,
            treeRoot.standardizedFileURL == lastRepositoryRoot.standardizedFileURL
        else { return }
        attach(root: lastRepositoryRoot)
    }

    private func attach(root: URL) {
        generation &+= 1
        let generation = generation

        // In a linked worktree `.git` is a pointer file, and its HEAD and shared refs can live outside `root`.
        let location = GitMetadataLocation.resolve(root: Self.normalizedPath(root), read: Self.readGitMetadataFile)
        let paths = WatchedPaths(
            root: Self.normalizedPath(root),
            gitDir: location.gitDir,
            head: location.gitDir + "/HEAD",
            packedRefs: location.commonDir + "/packed-refs",
            refs: location.commonDir + "/refs")

        let watcher = makeWatcher()
        self.watcher = watcher

        consumerTask = taskProvider.task(role: .observation) { [weak self] in
            await watcher.watchDirectory(paths.root)
            await watcher.watchFile(paths.head)
            await watcher.watchFile(paths.packedRefs)
            await watcher.watchDirectory(paths.refs)
            for await event in watcher.events {
                guard let self, self.generation == generation else { return }
                self.route(event, paths: paths, generation: generation)
            }
        }
    }

    /// The standardized path without the trailing `/` a directory URL carries: the prefix checks in
    /// ``classify(_:paths:)`` assume exactly one `/` between a directory and its contents.
    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// Reads a small git metadata file whole, or nil when it is a directory, missing or unreadable.
    private static func readGitMetadataFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func route(_ event: FileWatcher.FileWatchEvent, paths: WatchedPaths, generation: Int) {
        let path: String
        switch event {
            case .fileChanged(let changed): path = changed
            case .directoryChanged(let changed): path = changed
        }
        switch Self.classify(path, paths: paths) {
            case .tree:
                schedule(&treeTask, after: treeDebounce, generation: generation) { [weak self] in
                    self?.onTreeChanged?()
                }
            case .head:
                schedule(&headTask, after: refDebounce, generation: generation) { [weak self] in
                    self?.onHeadChanged?()
                }
            case .refs:
                schedule(&refsTask, after: refDebounce, generation: generation) { [weak self] in
                    self?.onRefsChanged?()
                }
            case .ignored: break
        }
    }

    /// Trailing debounce: each call cancels the wait pending in `slot`, so `fire` runs once events stop for `duration`.
    private func schedule(
        _ slot: inout Task<Void, Never>?, after duration: Duration, generation: Int, fire: @escaping () -> Void
    ) {
        slot?.cancel()
        let clock = clock
        slot = taskProvider.task { [weak self] in
            try? await clock.sleep(for: duration)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            fire()
        }
    }

    /// Classifies an absolute path the watcher reported. HEAD and the refs must match before the git directory's
    /// prefix, which drops every other metadata change.
    static func classify(_ path: String, paths: WatchedPaths) -> Classification {
        if path == paths.head { return .head }
        if path == paths.packedRefs || path == paths.refs || path.hasPrefix(paths.refs + "/") { return .refs }
        if path == paths.gitDir || path.hasPrefix(paths.gitDir + "/") { return .ignored }
        guard path == paths.root || path.hasPrefix(paths.root + "/") else { return .ignored }
        let relative = path.dropFirst(paths.root.count).drop { $0 == "/" }
        // Mirrors the folder scan's exclusions, skipped directories and hidden paths alike: sourcekit-lsp's
        // background index writes under `.build` would otherwise turn every hover into a reload loop.
        let components = relative.split(separator: "/")
        let liesUnderExcludedComponent = components.dropLast()
            .contains { SourceLoader.skippedDirectories.contains(String($0)) || $0.hasPrefix(".") }
        let isHiddenFile = components.last?.hasPrefix(".") ?? true
        return (liesUnderExcludedComponent || isHiddenFile) ? .ignored : .tree
    }
}
