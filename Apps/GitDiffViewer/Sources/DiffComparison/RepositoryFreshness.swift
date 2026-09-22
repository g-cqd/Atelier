package import AemiCore
package import AtelierFileTree
package import DiffGit
package import Foundation

/// The surface ``RepositoryFreshness`` drives: exactly ``AtelierFileTree/FileWatcher``'s public API, restated as
/// a protocol so a test can inject a synthetic source instead of real FSEvents/`DispatchSource`. `FileWatcher`
/// conforms below with no extra code, since every requirement already matches one of its members.
package protocol WatchEventSource: Sendable {
    var events: AsyncStream<FileWatcher.FileWatchEvent> { get }
    func watchDirectory(_ path: String) async
    func watchFile(_ path: String) async
    func unwatchFile(_ path: String) async
    func stop() async
}

extension FileWatcher: WatchEventSource {}

/// Watches a working-tree comparison's on-disk files and `.git` metadata for changes made outside the app (a
/// branch switch, a pull, an edit in another editor), and tells its owner when to reload.
///
/// ## What it watches
/// One ``WatchEventSource`` per attached comparison, covering four paths: the tree root itself (recursive —
/// FSEvents streams are recursive by construction, so one directory watch on the root also covers every nested
/// folder, `refs/heads` and `refs/remotes` included), `.git/HEAD` and `.git/packed-refs` as individual files, and
/// `.git/refs` as a second directory watch (packed refs live in one file, but loose refs are one file per ref
/// under `refs/**`, and FSEvents' recursion covers that nesting the same way it covers the tree root).
///
/// ## Routing and debouncing
/// Every event is classified by path (``classify(_:)``) into the working tree, `.git/HEAD`, refs (loose or
/// packed), or other `.git` noise (an index lock, a commit message editor's swap file) that is dropped outright.
/// A tree event under a path git-ignores by convention (``AtelierSources/SourceLoader/skippedDirectories`` —
/// `node_modules`, `DerivedData`, and friends) is dropped too, the same way a directory scan would leave it out.
/// Surviving events are coalesced on a trailing debounce before the matching callback fires, so a git operation
/// that touches many files (a checkout, a rebase) produces one reload instead of dozens: 600 ms for the tree —
/// deliberately longer than ``AtelierDiagnostics/DiagnosticsSession``'s 250 ms tool-run debounce, so a save that
/// also re-triggers diagnostics never races a freshness reload for the same edit — and 150 ms for HEAD/refs, which
/// change as one small burst at the end of a git command rather than throughout it.
///
/// ## Lifecycle
/// ``comparisonChanged(rightSource:repositoryRoot:)`` tears down any previous watcher and attaches a new one when
/// the right side is the repository's own working tree; anything else (two refs, a patch, no comparison yet)
/// leaves it detached. ``setEnabled(_:)`` mirrors ``ViewerSettings/autoRefresh``: off tears down without forgetting
/// what is being compared, on re-attaches to it. Every attachment is generation-stamped so a superseded watcher's
/// late events — including ones already in flight when ``teardown()`` runs — can never reach the callbacks of the
/// one that replaced it.
@MainActor
package final class RepositoryFreshness {
    /// Where a watched path landed, hence which callback (if any) its event feeds.
    /// The five normalized paths one comparison watches, computed once at attach so classification stays a
    /// handful of prefix checks.
    struct WatchedPaths: Sendable {
        let root: String
        let gitDir: String
        let head: String
        let packedRefs: String
        let refs: String
    }

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
    /// Bumped by every ``teardown()`` and every ``attach(root:)``; a debounced callback or a routed event whose
    /// captured generation no longer matches is from a watcher that has already been replaced or torn down.
    private var generation = 0

    private var lastRightSource: ComparisonSource?
    private var lastRepositoryRoot: URL?
    package private(set) var isEnabled: Bool

    /// A tree file changed; the owner should reload the right side's entries.
    package var onTreeChanged: (() -> Void)?
    /// `.git/HEAD` changed — a branch switch, a commit, a checkout; the owner should treat this like a fresh
    /// comparison, since the working tree's diff base has moved.
    package var onHeadChanged: (() -> Void)?
    /// A loose or packed ref changed, HEAD aside — a fetch updated a remote-tracking branch, a branch was created
    /// or deleted; the owner should refresh repository info (branch/tag menus) without touching the diff itself.
    package var onRefsChanged: (() -> Void)?

    /// - Parameters:
    ///   - taskProvider: Spawns the watcher's consumer task and every debounce timer.
    ///   - isEnabled: The initial value, read from ``ViewerSettings/autoRefresh`` at attach time; kept in sync
    ///     afterwards through ``setEnabled(_:)``.
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
        // `taskProvider.task` inherits the caller's actor context by capturing `self`, which a deinit cannot do;
        // `watcher.stop()` only touches the (Sendable) watcher itself, so a bare `Task` — the one place in this
        // file that isn't routed through `taskProvider` — stands in for it here.
        if let watcher {
            Task { await watcher.stop() }
        }
    }

    /// Tells this instance what the comparison now is, so it can (re)attach to the right side's working tree, or
    /// detach when there no longer is one. Safe to call for every comparison, a patch's or a ref-to-ref one
    /// included: anything that is not `.directory` at `repositoryRoot` simply leaves this detached.
    package func comparisonChanged(rightSource: ComparisonSource?, repositoryRoot: URL?) {
        lastRightSource = rightSource
        lastRepositoryRoot = repositoryRoot
        refreshAttachment()
    }

    /// Mirrors ``ViewerSettings/autoRefresh``: turning it off tears the watcher down without forgetting the
    /// current comparison, turning it on re-attaches to whatever ``comparisonChanged(rightSource:repositoryRoot:)``
    /// last reported.
    package func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        refreshAttachment()
    }

    /// Stops watching and cancels every in-flight debounce, without forgetting the last comparison reported to
    /// ``comparisonChanged(rightSource:repositoryRoot:)`` (``setEnabled(_:)`` needs it to re-attach later).
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

        // `.git` may be a linked worktree's pointer file rather than a directory: its private `HEAD` and the
        // refs it shares with every other worktree of the same repository can both live entirely outside `root`,
        // so watching only what a plain repository's layout would suggest would never see either move.
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

    /// `URL.standardizedFileURL.path(percentEncoded:)` trails a `/` when the URL carries a directory hint (from
    /// `directoryHint: .isDirectory`, or simply because the path it was built from already ended in one) — harmless
    /// on its own, but every `hasPrefix(x + "/")` check in ``classify(_:paths:)``
    /// assumes exactly one `/` between a directory path and what's under it. Stripping it here, once, keeps every
    /// comparison correct regardless of how the caller's `URL` happened to be constructed.
    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// Reads a small git metadata file (`.git` itself, or a worktree git dir's `commondir`) whole, or nil when it
    /// cannot be read as text -- a directory (the plain-repository case), missing, or unreadable for any other
    /// reason. The seam ``GitMetadataLocation/resolve(root:read:)`` runs its resolution through.
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

    /// Trailing debounce shared by every event kind: a new event of the same kind cancels whatever wait is already
    /// running and restarts it, so `fire` only ever runs once the events stop for `duration` — the same
    /// cancel-and-resleep shape ``AtelierDiagnostics/DiagnosticsSession/analyze(_:)`` uses for its own debounce.
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

    /// Classifies an absolute path reported by the watcher. Order matters: `.git/HEAD` and `.git/refs`/
    /// `packed-refs` are checked before the general `.git/` prefix, so they route to their own callback instead of
    /// falling into the catch-all "other `.git` noise" bucket.
    static func classify(_ path: String, paths: WatchedPaths) -> Classification {
        if path == paths.head { return .head }
        if path == paths.packedRefs || path == paths.refs || path.hasPrefix(paths.refs + "/") { return .refs }
        if path == paths.gitDir || path.hasPrefix(paths.gitDir + "/") { return .ignored }
        guard path == paths.root || path.hasPrefix(paths.root + "/") else { return .ignored }
        let relative = path.dropFirst(paths.root.count).drop { $0 == "/" }
        // Mirrors BOTH of the folder scan's exclusion rules (`SourceLoader.DirectorySource`): the named
        // `skippedDirectories` (`node_modules`, `DerivedData`, `Pods`, `Carthage`) and `.skipsHiddenFiles`.
        // The hidden rule is load-bearing, not cosmetic: sourcekit-lsp's background indexer — started by this
        // very app's hover tier — writes continuously into `<root>/.build/index-build`, and treating those
        // writes as tree changes turned every hover into a reload loop. A change under a hidden component can
        // never be reflected by `right.reload()` anyway, exactly like the named skips.
        let components = relative.split(separator: "/")
        let liesUnderExcludedComponent = components.dropLast()
            .contains { SourceLoader.skippedDirectories.contains(String($0)) || $0.hasPrefix(".") }
        let isHiddenFile = components.last?.hasPrefix(".") ?? true
        return (liesUnderExcludedComponent || isHiddenFile) ? .ignored : .tree
    }
}
