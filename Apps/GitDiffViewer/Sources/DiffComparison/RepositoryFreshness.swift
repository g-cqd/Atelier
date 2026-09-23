package import AemiCore
package import AtelierFileTree
package import DiffGit
package import Foundation

/// The ``AtelierFileTree/FileWatcher`` API ``RepositoryFreshness`` drives, as a protocol so a test can inject a
/// synthetic source: one event stream over every directory watched.
package protocol WatchEventSource: Sendable {
    var events: AsyncStream<FileWatcher.FileWatchEvent> { get }
    func watchDirectory(_ path: String) async
    func stop() async
}

extension FileWatcher: WatchEventSource {}

/// Watches a working-tree comparison's files and git metadata for changes made outside the app (an edit in another
/// editor, a `git add`, a commit, a checkout, a fetch) and tells its owner what to read again. One FSEvents stream
/// covers the tree and both git dirs, which a linked worktree keeps outside the tree; git's renames of `HEAD`, the
/// index and the refs arrive as changes to those paths, however often git replaces the files. The stream outlives
/// every reload of the same comparison, so a save made while a reload runs keeps its pending debounce. Each kind of
/// change fires its callback on a trailing debounce, so a git operation touching many files produces one reload.
@MainActor
package final class RepositoryFreshness {
    /// The paths one comparison watches, canonical as FSEvents reports them: symlinks resolved, and `/var/…`
    /// spelled `/private/var/…`.
    struct WatchedPaths: Sendable, Equatable {
        /// The working tree's root.
        let root: String
        /// This worktree's own git dir, holding its `HEAD` and index: `<root>/.git` in a plain repository.
        let gitDir: String
        /// The git dir every worktree of the repository shares, holding the refs: ``gitDir`` in a plain repository.
        let commonDir: String

        var head: String { gitDir + "/HEAD" }
        /// The index, which staging, unstaging and committing rewrite.
        var index: String { gitDir + "/index" }
        var refs: String { commonDir + "/refs" }
        var packedRefs: String { commonDir + "/packed-refs" }

        /// What the one stream watches, each directory once: the root holds both git dirs in a plain repository,
        /// and in a linked worktree the common dir holds the private one.
        var directories: [String] {
            [root, gitDir, commonDir]
                .reduce(into: []) { unique, directory in
                    if !unique.contains(directory) { unique.append(directory) }
                }
        }
    }

    /// What a reported path means for the comparison, hence which callbacks its event feeds.
    enum Classification: Equatable {
        /// A file or folder of the working tree, named relative to its root.
        case tree(String)
        case head
        case refs
        case index
        /// A directory holding what the watcher follows. FSEvents reports one when it lost track of the changes below
        /// it, and the watcher when its buffer overflowed: anything below may have changed. `HEAD`, the refs and the
        /// index are read again, and the tree too when it lies below.
        case rescan(includesTree: Bool)
        case ignored
    }

    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let treeDebounce: Duration
    private let refDebounce: Duration
    private let makeWatcher: @Sendable () -> any WatchEventSource

    private var watcher: (any WatchEventSource)?
    /// The paths the running watcher follows; nil while none runs. The same paths keep the watcher, and with it the
    /// pending debounces, across every reload of one comparison.
    private var attachedPaths: WatchedPaths?
    private var consumerTask: Task<Void, Never>?
    private var treeTask: Task<Void, Never>?
    private var headTask: Task<Void, Never>?
    private var refsTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    /// The tree paths written since the last tree callback, relative to the root; ``treeChangeFilter`` judges them.
    private var pendingTreePaths: Set<String> = []
    /// Whether the stream lost track of the tree since the last tree callback, which reloads without asking.
    private var isTreeRescanPending = false
    /// Bumped by every ``teardown()`` and every attach; events and debounces from an older generation are dropped.
    private var generation = 0

    private var lastRightSource: ComparisonSource?
    private var lastRepositoryRoot: URL?
    package private(set) var isEnabled: Bool

    /// Judges the tree paths written since the last reload, relative to the tree's root: true when a reload can show
    /// one of them. Awaited inside the tree debounce, so a write arriving meanwhile supersedes the judgment and hands
    /// its paths over again with the new one. Nil reloads for every write.
    package var treeChangeFilter: (@MainActor (_ paths: Set<String>) async -> Bool)?
    /// A tree file changed in a way a reload can show; the owner should reload the right side's entries.
    package var onTreeChanged: (() -> Void)?
    /// `HEAD` changed, as a checkout or a branch switch leaves it: a side on `HEAD` may now name another commit.
    package var onHeadChanged: (() -> Void)?
    /// A loose or packed ref changed, as a commit, a fetch or a new branch or tag leaves it.
    package var onRefsChanged: (() -> Void)?
    /// The index changed, as staging, unstaging or a commit leaves it; the owner should re-read git's status, not
    /// the files, whose contents did not change.
    package var onIndexChanged: (() -> Void)?

    /// - Parameters:
    ///   - taskProvider: Spawns the watcher's consumer task and every debounce timer.
    ///   - isEnabled: The initial ``ViewerSettings/autoRefresh``; later changes arrive through ``setEnabled(_:)``.
    ///   - clock: Drives the debounces; tests inject a virtual one.
    ///   - treeDebounce: Trailing coalesce for working-tree events; kept above the diagnostics session's own
    ///     debounce so a refresh never races the analysis it triggers.
    ///   - refDebounce: Trailing coalesce for `HEAD`, ref and index events, short since they arrive alone.
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
        indexTask?.cancel()
        // A bare `Task`: `taskProvider.task` would capture `self`, which a deinit cannot do.
        if let watcher {
            Task { await watcher.stop() }
        }
    }

    /// Attaches to the right side when it is the working tree at `repositoryRoot`, and detaches otherwise. The same
    /// comparison again, as every reload reports it, keeps the running watcher.
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

    /// Stops watching and cancels every pending debounce, keeping the last comparison so a later
    /// ``comparisonChanged(rightSource:repositoryRoot:)`` or ``setEnabled(_:)`` attaches afresh.
    package func teardown() {
        generation &+= 1
        attachedPaths = nil
        pendingTreePaths = []
        isTreeRescanPending = false
        consumerTask?.cancel()
        consumerTask = nil
        treeTask?.cancel()
        treeTask = nil
        headTask?.cancel()
        headTask = nil
        refsTask?.cancel()
        refsTask = nil
        indexTask?.cancel()
        indexTask = nil
        guard let watcher else { return }
        self.watcher = nil
        taskProvider.task { await watcher.stop() }
    }

    /// Attaches, detaches or keeps the watcher. The check comes before ``teardown()``, which would stop the stream
    /// and drop the pending debounces of a comparison that did not change; it compares every watched path, so a git
    /// dir that moved attaches afresh.
    private func refreshAttachment() {
        let desired = desiredPaths()
        guard desired != attachedPaths else { return }
        teardown()
        guard let desired else { return }
        attach(desired)
    }

    /// The paths to watch for the last comparison: none while disabled, or unless the right side is the
    /// repository's own working tree.
    private func desiredPaths() -> WatchedPaths? {
        guard isEnabled, case .directory(let treeRoot) = lastRightSource, let repositoryRoot = lastRepositoryRoot
        else { return nil }
        // Git names the root by its real path, while a folder chosen through a symlink keeps the link's.
        let root = Self.canonical(Self.normalizedPath(repositoryRoot))
        guard Self.canonical(Self.normalizedPath(treeRoot)) == root else { return nil }
        // In a linked worktree `.git` is a pointer file, and its HEAD and shared refs live outside the root.
        let location = GitMetadataLocation.resolve(root: root, read: Self.readGitMetadataFile)
        return WatchedPaths(
            root: root, gitDir: Self.canonical(location.gitDir), commonDir: Self.canonical(location.commonDir))
    }

    private func attach(_ paths: WatchedPaths) {
        generation &+= 1
        let generation = generation
        attachedPaths = paths
        let watcher = makeWatcher()
        self.watcher = watcher
        consumerTask = taskProvider.task(role: .observation) { [weak self] in
            for directory in paths.directories {
                await watcher.watchDirectory(directory)
            }
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

    /// `path` as FSEvents reports it, symlinks resolved as far as the path exists.
    private static func canonical(_ path: String) -> String {
        FileWatcher.canonicalPaths(forFile: path).first ?? path
    }

    /// Reads a small git metadata file whole, or nil when it is a directory, missing or unreadable.
    private static func readGitMetadataFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func route(_ event: FileWatcher.FileWatchEvent, paths: WatchedPaths, generation: Int) {
        let path =
            switch event {
                case .fileChanged(let changed), .directoryChanged(let changed): changed
            }
        switch Self.classify(path, paths: paths) {
            case .tree(let relative):
                pendingTreePaths.insert(relative)
                scheduleTreeCheck(generation: generation)
            case .head:
                scheduleHeadChange(generation: generation)
            case .refs:
                scheduleRefsChange(generation: generation)
            case .index:
                scheduleIndexChange(generation: generation)
            case .rescan(let includesTree):
                if includesTree {
                    isTreeRescanPending = true
                    scheduleTreeCheck(generation: generation)
                }
                scheduleHeadChange(generation: generation)
                scheduleRefsChange(generation: generation)
                scheduleIndexChange(generation: generation)
            case .ignored: break
        }
    }

    private func scheduleTreeCheck(generation: Int) {
        schedule(&treeTask, after: treeDebounce, generation: generation) { [weak self] in
            await self?.flushTreeChanges(generation: generation)
        }
    }

    private func scheduleHeadChange(generation: Int) {
        schedule(&headTask, after: refDebounce, generation: generation) { [weak self] in self?.onHeadChanged?() }
    }

    private func scheduleRefsChange(generation: Int) {
        schedule(&refsTask, after: refDebounce, generation: generation) { [weak self] in self?.onRefsChanged?() }
    }

    private func scheduleIndexChange(generation: Int) {
        schedule(&indexTask, after: refDebounce, generation: generation) { [weak self] in self?.onIndexChanged?() }
    }

    /// Hands the tree paths written since the last reload to ``treeChangeFilter`` and reloads when it finds one a
    /// reload can show; a rescan reloads without asking. A write arriving while the filter runs cancels this check,
    /// which then keeps every path for the next one.
    private func flushTreeChanges(generation: Int) async {
        let paths = pendingTreePaths
        let isRescan = isTreeRescanPending
        var reloads = isRescan
        if !reloads, !paths.isEmpty {
            reloads = await treeChangeFilter?(paths) ?? true
        }
        guard !Task.isCancelled, self.generation == generation else { return }
        pendingTreePaths.subtract(paths)
        if isRescan { isTreeRescanPending = false }
        if reloads { onTreeChanged?() }
    }

    /// Trailing debounce: each call cancels the wait pending in `slot`, so `fire` runs once events stop for `duration`.
    private func schedule(
        _ slot: inout Task<Void, Never>?, after duration: Duration, generation: Int,
        fire: @escaping @MainActor () async -> Void
    ) {
        slot?.cancel()
        let clock = clock
        slot = taskProvider.task { [weak self] in
            try? await clock.sleep(for: duration)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            await fire()
        }
    }

    /// Classifies an absolute, canonical path the watcher reported. `HEAD`, the index and the refs match before the
    /// git dirs' prefixes, which drop every other metadata change: objects, logs, locks, `FETCH_HEAD`. A watched
    /// directory itself, or one above it, only arrives when the stream lost track of what changed below. A tree path
    /// under a directory the listing always skips is dropped here; every other one goes to ``treeChangeFilter``.
    nonisolated static func classify(_ path: String, paths: WatchedPaths) -> Classification {
        if path == paths.head { return .head }
        if path == paths.index { return .index }
        if path == paths.packedRefs || isInside(path, paths.refs) { return .refs }
        if isInside(paths.root, path) { return .rescan(includesTree: true) }
        if isInside(paths.gitDir, path) || isInside(paths.commonDir, path) { return .rescan(includesTree: false) }
        if isInside(path, paths.gitDir) || isInside(path, paths.commonDir) { return .ignored }
        guard isInside(path, paths.root) else { return .ignored }
        let relative = String(path.dropFirst(paths.root.count + 1))
        let liesUnderSkippedDirectory = relative.split(separator: "/").dropLast()
            .contains { SourceLoader.skippedDirectories.contains(String($0)) }
        return liesUnderSkippedDirectory ? .ignored : .tree(relative)
    }

    /// Whether `path` is `directory` or lies below it.
    private nonisolated static func isInside(_ path: String, _ directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }
}
