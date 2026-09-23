import Foundation
import Synchronization
import os

/// Watches directories and individual files through one FSEvents stream, surfacing both as one consumer-driven
/// `AsyncStream`.
///
/// Every watched directory, and the parent directory of every watched file, joins a single stream. A call that
/// changes that set restarts the stream from the last event the old one delivered, so no change made in between is
/// lost. Paths are keyed by `realpath(3)`, the spelling FSEvents reports (`/tmp/a` arrives as `/private/tmp/a`), and
/// a file watch follows its path, not its inode, so it survives the atomic saves that rename a new file over it.
///
/// FSEvents calls back on the watcher's serial queue and yields straight to the stream's continuation, so the
/// watcher starts no task of its own. Suppression reads `ContinuousClock` directly; ``SuppressionWindow`` takes
/// explicit times, so its tests need no clock.
public actor FileWatcher {
    /// A change the watcher reports.
    public enum FileWatchEvent: Sendable, Equatable {
        /// A watched file may have changed: it was written, replaced, renamed or removed, or FSEvents lost track of
        /// its directory. The path is the one given to ``FileWatcher/watchFile(_:)``.
        case fileChanged(String)
        /// Something else changed in a watched directory or next to a watched file. The path is canonical, as
        /// FSEvents reports it: symlinks resolved, and `/tmp/a` spelled `/private/tmp/a`.
        case directoryChanged(String)
    }

    /// Why ``FileWatcher/excludeDirectories(_:)`` refused its paths.
    public enum ExclusionError: Error, Equatable {
        /// FSEvents takes at most ``FileWatcher/maximumExcludedDirectories`` paths; the payload is how many were given.
        case tooManyDirectories(Int)
    }

    /// Paths the app wrote itself, each suppressed for `window` after it was recorded. A `Mutex` rather than the actor
    /// guards it, so event handlers running outside any task consult it without an `await`.
    final class SuppressionWindow: Sendable {
        private let timestamps = Mutex<[String: Duration]>([:])
        private let window: Duration

        init(window: Duration) {
            self.window = window
        }

        func record(_ path: String, now: Duration) {
            timestamps.withLock { table in
                table[path] = now
                // Opportunistic cleanup: every insertion also evicts any entry whose suppression
                // window has already elapsed. Without this, a path whose suppression record never
                // sees a matching fsevent stays in the dictionary forever — over a long session of
                // rename/delete ops, memory grows linearly with the count of suppressed paths.
                if table.count > 1 {
                    table = table.filter { now - $0.value < window }
                }
            }
        }

        func isSuppressed(_ path: String, now: Duration) -> Bool {
            timestamps.withLock { table in
                guard let recordedAt = table[path] else { return false }
                if now - recordedAt < window {
                    return true
                }
                table.removeValue(forKey: path)
                return false
            }
        }
    }

    /// The most directories ``excludeDirectories(_:)`` accepts: FSEvents' own limit.
    public static let maximumExcludedDirectories = 8
    /// How many events wait for a consumer that falls behind. Past it the oldest are dropped, and the watcher then
    /// reports every watched file and directory once more, so a slow consumer rescans instead of missing a change.
    public static let eventBufferLimit = 1_024

    nonisolated public let events: AsyncStream<FileWatchEvent>
    private nonisolated let continuation: AsyncStream<FileWatchEvent>.Continuation
    private nonisolated let epoch: ContinuousClock.Instant
    private nonisolated let suppression: SuppressionWindow
    private nonisolated let stream: EventStreamController
    private var table = WatchTable()
    /// Each watched file's registered path, with the canonical keys its events arrive under.
    private var watchedFiles: [String: [String]] = [:]
    private var isStopped = false

    public init() {
        self.init(latency: 0.1, suppressionWindow: .seconds(1))
    }

    /// - Parameters:
    ///   - latency: How long FSEvents coalesces events before delivering them, in seconds.
    ///   - suppressionWindow: How long ``suppressNotifications(for:)`` silences a path.
    init(latency: TimeInterval, suppressionWindow: Duration) {
        let (events, continuation) = AsyncStream.makeStream(
            of: FileWatchEvent.self, bufferingPolicy: .bufferingNewest(Self.eventBufferLimit))
        let epoch = ContinuousClock.now
        let suppression = SuppressionWindow(window: suppressionWindow)
        self.events = events
        self.continuation = continuation
        self.epoch = epoch
        self.suppression = suppression
        self.stream = EventStreamController(
            latency: latency, continuation: continuation, suppression: suppression, epoch: epoch)
    }

    /// Reports every later change below `path`. Several directories share one stream, restarted over their union with
    /// no event lost. Does nothing for a directory already watched, or after ``stop()``.
    /// - Complexity: O(w²) in the watched directories and files, to recompute the stream's paths.
    public func watchDirectory(_ path: String) {
        let requestedAt = FSEventsGetCurrentEventId()
        guard !isStopped, table.insertDirectory(CanonicalPath.of(path), since: requestedAt) else { return }
        stream.apply(table, requestedAt: requestedAt)
    }

    /// Reports later changes to the file at `path` as ``FileWatchEvent/fileChanged(_:)`` carrying `path` itself. The
    /// watch listens to the parent directory, so it outlives atomic saves, and the file need not exist yet; the
    /// siblings' changes arrive as ``FileWatchEvent/directoryChanged(_:)``. Does nothing for a file already watched,
    /// or after ``stop()``.
    /// - Complexity: O(w²) in the watched directories and files, to recompute the stream's paths.
    public func watchFile(_ path: String) {
        let requestedAt = FSEventsGetCurrentEventId()
        guard !isStopped, watchedFiles[path] == nil else { return }
        let keys = CanonicalPath.keys(forFile: path)
        watchedFiles[path] = keys
        table.insertFile(path, keys: keys, since: requestedAt)
        stream.apply(table, requestedAt: requestedAt)
    }

    /// Stops reporting `path` as a watched file: its later changes arrive as directory changes while its directory
    /// stays watched for another reason.
    /// - Complexity: O(w²) in the watched directories and files, to recompute the stream's paths.
    public func unwatchFile(_ path: String) {
        let requestedAt = FSEventsGetCurrentEventId()
        guard let keys = watchedFiles.removeValue(forKey: path) else { return }
        table.removeFile(path, keys: keys)
        stream.apply(table, requestedAt: requestedAt)
    }

    /// Filters every change below each of `paths` out of the stream, inside FSEvents, replacing earlier exclusions. A
    /// watched file below an excluded directory goes silent too. Does nothing after ``stop()``.
    /// - Parameter paths: At most ``maximumExcludedDirectories`` directories.
    /// - Throws: ``ExclusionError/tooManyDirectories(_:)`` when `paths` holds more, leaving the exclusions unchanged.
    public func excludeDirectories(_ paths: [String]) throws(ExclusionError) {
        guard paths.count <= Self.maximumExcludedDirectories else { throw .tooManyDirectories(paths.count) }
        let requestedAt = FSEventsGetCurrentEventId()
        guard !isStopped else { return }
        table.exclusions = paths.map(CanonicalPath.of)
        stream.apply(table, requestedAt: requestedAt)
    }

    /// Marks `path` as written by the app, so events of either kind for it in the next second are dropped rather than
    /// reported as external changes. Callable from any isolation without an `await`.
    public nonisolated func suppressNotifications(for path: String) {
        let now = epoch.duration(to: ContinuousClock.now)
        for key in CanonicalPath.keys(forFile: path) {
            suppression.record(key, now: now)
        }
    }

    /// The canonical paths under which events for the file at `path` arrive: its `realpath(3)` target and, when `path`
    /// is a symlink, the link's own location. A consumer that matches ``FileWatchEvent/directoryChanged(_:)`` paths to
    /// its own files compares against these.
    public static func canonicalPaths(forFile path: String) -> [String] {
        CanonicalPath.keys(forFile: path)
    }

    /// Stops watching and finishes ``events``; the watch methods do nothing afterwards.
    public func stop() {
        guard !isStopped else { return }
        isStopped = true
        watchedFiles.removeAll()
        table = WatchTable()
        stream.invalidate()
        continuation.finish()
    }

    /// Returns once the stream has applied every earlier watch, unwatch and exclusion, so a test's next write lands in
    /// the stream those calls configured.
    func synchronizeStream() async {
        await stream.synchronize()
    }

    deinit {
        stream.invalidate()
        continuation.finish()
    }
}

/// What one ``FileWatcher`` watches, and how FSEvents' raw events map onto its ``FileWatcher/FileWatchEvent``s.
struct WatchTable: Sendable, Equatable {
    /// How the watcher answers one raw FSEvents event.
    enum Route: Equatable {
        /// Report nothing: FSEvents' end-of-history marker, an event older than its watch, or a suppressed path.
        case skip
        /// Report ``FileWatcher/FileWatchEvent/fileChanged(_:)`` for each of these registered paths.
        case files([String])
        /// Report ``FileWatcher/FileWatchEvent/directoryChanged(_:)`` for this canonical path.
        case directory(String)
        /// FSEvents coalesced or dropped the events below this path: report everything watched there.
        case rescan(String)
    }

    /// A canonical path a watched file answers to.
    struct FileKey: Sendable, Equatable {
        /// The paths the caller registered for this key, in the order it watched them.
        var registered: [String]
        /// The directory whose events carry this key's changes.
        var parent: String
        /// The system's event ID when the earliest of `registered` was watched.
        var since: FSEventStreamEventId
    }

    /// Canonical directories the caller asked to watch, each with the system's event ID when it asked.
    private(set) var directories: [String: FSEventStreamEventId] = [:]
    /// The watched files' canonical keys.
    private(set) var fileKeys: [String: FileKey] = [:]
    /// Canonical directories FSEvents filters out.
    var exclusions: [String] = []
    /// The latest `since` of any watch: every event after it is new to every watch.
    private(set) var newestSince: FSEventStreamEventId = 0

    /// The fewest directories covering `directories` and each watched file's parent, sorted: the stream's paths.
    /// - Complexity: O(w²) in the watched directories and files.
    var roots: [String] {
        CanonicalPath.minimalCover(Array(directories.keys) + fileKeys.values.map(\.parent))
    }

    /// Watches canonical `directory` from event `since` on.
    /// - Returns: False when `directory` was already watched, which leaves it watched from its first `since`.
    mutating func insertDirectory(_ directory: String, since: FSEventStreamEventId) -> Bool {
        guard directories[directory] == nil else { return false }
        directories[directory] = since
        newestSince = max(newestSince, since)
        return true
    }

    /// Reports `registered` for each of its canonical `keys` from event `since` on.
    mutating func insertFile(_ registered: String, keys: [String], since: FSEventStreamEventId) {
        for key in keys {
            if fileKeys[key] == nil {
                fileKeys[key] = FileKey(registered: [], parent: CanonicalPath.parent(of: key), since: since)
            }
            fileKeys[key]?.registered.append(registered)
        }
        newestSince = max(newestSince, since)
    }

    /// Stops reporting `registered` for its canonical `keys`, dropping each key no other path answers to.
    mutating func removeFile(_ registered: String, keys: [String]) {
        for key in keys {
            fileKeys[key]?.registered.removeAll { $0 == registered }
            if fileKeys[key]?.registered.isEmpty == true {
                fileKeys[key] = nil
            }
        }
    }

    /// How to answer one raw event at canonical `path`.
    /// - Parameters:
    ///   - path: The canonical path FSEvents reported.
    ///   - flags: The event's `kFSEventStreamEventFlag…` bits.
    ///   - id: The event's system-wide ID.
    ///   - isSuppressed: Whether the app wrote `path` itself moments ago.
    /// - Returns: What to report for the event.
    func route(
        path: String, flags: FSEventStreamEventFlags, id: FSEventStreamEventId, isSuppressed: (String) -> Bool
    ) -> Route {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 { return .skip }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 { return .rescan(path) }
        if isStale(path, id: id) || isSuppressed(path) { return .skip }
        if let key = fileKeys[path] { return .files(key.registered) }
        return .directory(path)
    }

    /// Whether event `id` at `path` predates every watch covering `path`, or no watch covers it. A restarted stream
    /// replays history from before its restart, and such events in it are stale news.
    /// - Complexity: O(1) for an event newer than every watch, else O(w) in the watched directories and files.
    func isStale(_ path: String, id: FSEventStreamEventId) -> Bool {
        guard id <= newestSince else { return false }
        var earliest: FSEventStreamEventId?
        for (directory, since) in directories where CanonicalPath.isInside(path, directory) {
            earliest = min(earliest ?? since, since)
        }
        for key in fileKeys.values where CanonicalPath.isInside(path, key.parent) {
            earliest = min(earliest ?? key.since, key.since)
        }
        guard let earliest else { return true }
        return id <= earliest
    }

    /// The events that make a consumer rescan below `path`: every watched file there, then `path` itself when the
    /// stream covers it, else each watched directory below it. `/` lists everything watched.
    /// - Complexity: O(w log w) in the watched directories and files.
    func rescanEvents(below path: String) -> [FileWatcher.FileWatchEvent] {
        var events: [FileWatcher.FileWatchEvent] = []
        for (key, file) in fileKeys.sorted(by: { $0.key < $1.key }) where CanonicalPath.isInside(key, path) {
            events += file.registered.map(FileWatcher.FileWatchEvent.fileChanged)
        }
        if roots.contains(where: { CanonicalPath.isInside(path, $0) }) {
            events.append(.directoryChanged(path))
        } else {
            events += directories.keys.sorted().filter { CanonicalPath.isInside($0, path) }
                .map(FileWatcher.FileWatchEvent.directoryChanged)
        }
        return events
    }
}

/// Canonical spellings of paths, as FSEvents reports them: every symlink resolved, `/tmp` spelled `/private/tmp`.
enum CanonicalPath {
    /// `path` with its symlinks resolved by `realpath(3)` as far as it exists, and its missing components appended as
    /// given, so a file not created yet canonicalizes too. A path no prefix of which resolves comes back unchanged.
    /// - Complexity: One `realpath` call per missing trailing component, plus one.
    static func of(_ path: String) -> String {
        var end = path.endIndex
        var missing: [Substring] = []
        while true {
            let prefix = path[..<end]
            if let resolved = resolved(prefix.isEmpty ? "." : String(prefix)) {
                return missing.reversed().reduce(resolved) { joined($0, $1) }
            }
            guard let slash = prefix.lastIndex(of: "/") else {
                // A relative path: the missing components then hang off the working directory.
                guard !prefix.isEmpty else { return path }
                missing.append(prefix)
                end = prefix.startIndex
                continue
            }
            let parentEnd = slash == path.startIndex ? path.index(after: slash) : slash
            guard parentEnd < end else { return path }
            let component = path[path.index(after: slash) ..< end]
            if !component.isEmpty {
                missing.append(component)
            }
            end = parentEnd
        }
    }

    /// The canonical paths a watched file's events arrive under: its target, and also the link's own location when
    /// `path` is a symlink, since an atomic save through the link replaces it.
    static func keys(forFile path: String) -> [String] {
        let target = of(path)
        let location = joined(of(parent(of: path)), Substring(lastComponent(of: path)))
        return target == location ? [target] : [target, location]
    }

    /// `path` up to its last `/`: `/` for a top-level path, `.` for a bare name.
    static func parent(of path: String) -> String {
        let trimmed = trimmingTrailingSlashes(path)
        guard let slash = trimmed.lastIndex(of: "/") else { return "." }
        return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    }

    /// Whether `path` is `directory` or lies below it, comparing bytes.
    static func isInside(_ path: String, _ directory: String) -> Bool {
        let pathBytes = path.utf8
        let directoryBytes = directory.utf8
        guard pathBytes.starts(with: directoryBytes) else { return false }
        if directoryBytes.last == UInt8(ascii: "/") { return true }
        let rest = pathBytes.dropFirst(directoryBytes.count)
        return rest.isEmpty || rest.first == UInt8(ascii: "/")
    }

    /// The fewest of `directories` that still cover every one of them, sorted.
    /// - Complexity: O(n²) in the directories.
    static func minimalCover(_ directories: some Sequence<String>) -> [String] {
        var cover: [String] = []
        for directory in Set(directories).sorted(by: { $0.utf8.count < $1.utf8.count })
        where !cover.contains(where: { isInside(directory, $0) }) {
            cover.append(directory)
        }
        return cover.sorted()
    }

    /// `realpath(3)` of `path`, or nil when a component is missing or unreadable.
    private static func resolved(_ path: String) -> String? {
        // `realpath` returns a `malloc`ed buffer, freed here once copied into the `String`.
        guard let buffer = realpath(path, nil) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }

    private static func joined(_ base: String, _ component: Substring) -> String {
        base.hasSuffix("/") ? base + component : base + "/" + component
    }

    private static func lastComponent(of path: String) -> Substring {
        let trimmed = trimmingTrailingSlashes(path)
        guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
        return trimmed[trimmed.index(after: slash)...]
    }

    private static func trimmingTrailingSlashes(_ path: String) -> Substring {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

private let logger = Logger(subsystem: "Atelier.FileTree", category: "FileWatcher")

/// The FSEvents stream of one ``FileWatcher``, and the serial queue it calls back on.
///
/// Memory safety rests on two rules. FSEvents owns this controller through the context's `retain` and `release`
/// callbacks, so `info` stays valid for as long as a stream exists, however late a callback runs. And every operation
/// on a stream, creation, restart and teardown included, runs on `queue`, so none can interleave with a callback in
/// flight. The queue is required: FSEvents' only non-deprecated scheduling API takes one.
private final class EventStreamController: @unchecked Sendable {
    // Invariant: every `var` is read and written only on `queue`.
    private let queue = DispatchQueue(label: "Atelier.FileWatcher.events", qos: .utility)
    private let latency: TimeInterval
    private let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation
    private let suppression: FileWatcher.SuppressionWindow
    private let epoch: ContinuousClock.Instant
    private var table = WatchTable()
    private var stream: FSEventStreamRef?
    /// The paths and exclusions `stream` was created with; empty while none runs.
    private var streamRoots: [String] = []
    private var streamExclusions: [String] = []
    private var isInvalidated = false

    init(
        latency: TimeInterval, continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation,
        suppression: FileWatcher.SuppressionWindow, epoch: ContinuousClock.Instant
    ) {
        self.latency = latency
        self.continuation = continuation
        self.suppression = suppression
        self.epoch = epoch
    }

    /// Routes later events through `table`, restarting the stream when its paths or exclusions changed.
    /// - Parameters:
    ///   - table: What the watcher now watches.
    ///   - requestedAt: The system's event ID when the caller asked.
    func apply(_ table: WatchTable, requestedAt: FSEventStreamEventId) {
        queue.async { [self] in
            guard !isInvalidated else { return }
            self.table = table
            let roots = table.roots
            guard roots != streamRoots || table.exclusions != streamExclusions else { return }
            restart(over: roots, requestedAt: requestedAt)
        }
    }

    /// Tears the stream down for good; later ``apply(_:requestedAt:)`` calls do nothing.
    func invalidate() {
        queue.async { [self] in
            isInvalidated = true
            _ = tearDown()
        }
    }

    /// Returns once every block queued before it has run.
    func synchronize() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    /// Replaces the running stream with one over `roots`. The new stream replays history from the older of
    /// `requestedAt` and the last event the old one delivered, so nothing either would have reported is lost; what it
    /// replays from before a watch began, ``WatchTable/isStale(_:id:)`` drops, and what it replays twice, consumers
    /// already take as a repeated change.
    private func restart(over roots: [String], requestedAt: FSEventStreamEventId) {
        let latest = tearDown()
        guard !roots.isEmpty else { return }
        guard let stream = makeStream(over: roots, since: min(latest ?? requestedAt, requestedAt)) else {
            logger.error("FSEvents refused a stream over \(roots.count, privacy: .public) directories")
            return
        }
        if !table.exclusions.isEmpty, !FSEventStreamSetExclusionPaths(stream, table.exclusions as CFArray) {
            logger.error("FSEvents refused \(self.table.exclusions.count, privacy: .public) exclusion paths")
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            logger.error("FSEvents could not start a stream over \(roots.count, privacy: .public) directories")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
        streamRoots = roots
        streamExclusions = table.exclusions
    }

    /// Stops and releases the running stream.
    /// - Returns: The last event ID it delivered, or nil when no stream ran.
    private func tearDown() -> FSEventStreamEventId? {
        guard let stream else { return nil }
        FSEventStreamStop(stream)
        let latest = FSEventStreamGetLatestEventId(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        streamRoots = []
        streamExclusions = []
        return latest
    }

    private func makeStream(over roots: [String], since: FSEventStreamEventId) -> FSEventStreamRef? {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<EventStreamController>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<EventStreamController>.fromOpaque(info).release()
            },
            copyDescription: nil)
        return FSEventStreamCreate(
            nil,
            { _, info, count, eventPaths, eventFlags, eventIds in
                guard let info,
                    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
                else { return }
                // FSEvents lends `count` flags and IDs for the duration of this call only; `receive` reads them
                // synchronously and keeps neither buffer.
                Unmanaged<EventStreamController>.fromOpaque(info).takeUnretainedValue()
                    .receive(
                        paths: paths, flags: UnsafeBufferPointer(start: eventFlags, count: count),
                        ids: UnsafeBufferPointer(start: eventIds, count: count))
            },
            &context,
            roots as CFArray,
            since,
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
    }

    /// Routes one callback's events and yields them; runs on `queue`. When the buffer overflows, everything watched is
    /// reported once more at the end, the newest events and so the ones kept.
    private func receive(
        paths: [String], flags: UnsafeBufferPointer<FSEventStreamEventFlags>,
        ids: UnsafeBufferPointer<FSEventStreamEventId>
    ) {
        let now = epoch.duration(to: ContinuousClock.now)
        var overflowed = false
        func report(_ event: FileWatcher.FileWatchEvent) {
            if case .dropped = continuation.yield(event) {
                overflowed = true
            }
        }
        for index in 0 ..< min(paths.count, flags.count, ids.count) {
            let route = table.route(
                path: paths[index], flags: flags[index], id: ids[index],
                isSuppressed: { suppression.isSuppressed($0, now: now) })
            switch route {
                case .skip:
                    continue
                case .files(let registered):
                    for path in registered {
                        report(.fileChanged(path))
                    }
                case .directory(let path):
                    report(.directoryChanged(path))
                case .rescan(let path):
                    for event in table.rescanEvents(below: path) {
                        report(event)
                    }
            }
        }
        guard overflowed else { return }
        for event in table.rescanEvents(below: "/") {
            continuation.yield(event)
        }
    }
}
