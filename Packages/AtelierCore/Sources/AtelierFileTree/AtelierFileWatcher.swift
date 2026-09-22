import Foundation
import Synchronization

/// Watches directories (FSEvents) and individual files (per-file `DispatchSource`) for changes,
/// surfacing both as a consumer-driven `AsyncStream`.
///
/// Core-tier shape: the actor exposes `async` functions and one `AsyncStream<FileWatchEvent>` the
/// caller drives with its own task — no `TaskProvider`, no unstructured `Task` spawned internally,
/// and no `AemiCore`/`AemiRuntime` `ClockInstant` erasure helper. `DispatchSource`/FSEvents are
/// event *sources*, not task primitives, so using them here does not violate the "no unstructured
/// tasks" rule: their callbacks run synchronously on a GCD queue and either write directly to the
/// (`Sendable`) stream continuation, or — for the self-write suppression window below — consult a
/// plain, lock-guarded, pure data structure with no actor hop and therefore no task needed to cross
/// isolation. The suppression window measures elapsed time against `ContinuousClock` directly
/// (rather than through an injected `any Clock<Duration>`): its own unit tests exercise the pure
/// `SuppressionWindow` type with synthetic `Duration`s, so nothing here needs a virtual clock.
public actor FileWatcher {
    public enum FileWatchEvent: Sendable {
        case fileChanged(String)
        case directoryChanged(String)
    }

    /// Pure, synchronous, independently testable self-write suppression window: `suppressNotifications`
    /// records a path at a point in time, `isSuppressed` answers whether that path is still inside the
    /// window. Backed by a `Mutex` (not the actor) so `DispatchSource` event handlers — which run outside
    /// any task — can consult it without an `await`.
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

    private var fileSources: [String: any DispatchSourceFileSystemObject] = [:]
    private var directoryStream: FSEventStreamRef?
    private var streamQueue: DispatchQueue?
    private var continuation: AsyncStream<FileWatchEvent>.Continuation?
    /// Strong reference to the box passed to `FSEventStreamCreate` so the
    /// callback's `info` pointer stays valid for the stream's lifetime.
    /// Cleared in `stop()` after the stream has been invalidated.
    private var directoryStreamBox: SendableContinuationBox?
    private nonisolated let epoch: ContinuousClock.Instant
    private nonisolated let suppression: SuppressionWindow

    private static let debounceInterval: TimeInterval = 0.1
    private static let suppressWindow: Duration = .seconds(1)

    nonisolated public let events: AsyncStream<FileWatchEvent>

    public init() {
        self.epoch = ContinuousClock.now
        self.suppression = SuppressionWindow(window: Self.suppressWindow)
        var captured: AsyncStream<FileWatchEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    public func watchDirectory(_ path: String) {
        guard directoryStream == nil else { return }

        let queue = DispatchQueue(label: "com.kittycode.fswatcher", qos: .utility)
        streamQueue = queue

        // Box ownership lives on `self`. Passing an unretained pointer into
        // `FSEventStreamContext.info` avoids relying on whether the CF API
        // honours the optional `retain` callback for that field.
        let box = SendableContinuationBox(continuation: continuation)
        directoryStreamBox = box

        var context = FSEventStreamContext()
        context.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())

        let paths = [path] as CFArray
        let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info,
                    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                        as? [String]
                else { return }
                let box = Unmanaged<SendableContinuationBox>.fromOpaque(info).takeUnretainedValue()
                for i in 0 ..< numEvents {
                    box.continuation?.yield(.directoryChanged(cfPaths[i]))
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.debounceInterval,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            directoryStream = stream
        } else {
            // Stream creation failed; drop the box so it gets deallocated.
            directoryStreamBox = nil
        }
    }

    public func watchFile(_ path: String) {
        guard fileSources[path] == nil else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .global(qos: .utility)
        )

        let capturedContinuation = continuation
        let capturedPath = path
        let capturedEpoch = epoch
        let capturedSuppression = suppression

        source.setEventHandler {
            // Runs on a GCD queue, outside any task. `ContinuousClock.now` is a synchronous, concrete
            // (non-existential) property read and `SuppressionWindow` is lock-guarded, so this
            // suppression check needs no actor hop and spawns no unstructured task.
            let elapsed = capturedEpoch.duration(to: ContinuousClock.now)
            if !capturedSuppression.isSuppressed(capturedPath, now: elapsed) {
                capturedContinuation?.yield(.fileChanged(capturedPath))
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileSources[path] = source
    }

    public func unwatchFile(_ path: String) {
        guard let source = fileSources.removeValue(forKey: path) else { return }
        source.cancel()
    }

    /// Marks `path` as self-written so the next matching fsevent (typically the app's own save) is
    /// dropped instead of round-tripping back as an external change. Synchronous and lock-based —
    /// no actor hop needed, so callers on any isolation can call it directly.
    public nonisolated func suppressNotifications(for path: String) {
        suppression.record(path, now: epoch.duration(to: ContinuousClock.now))
    }

    public func stop() {
        for (_, source) in fileSources {
            source.cancel()
        }
        fileSources.removeAll()

        if let stream = directoryStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            directoryStream = nil
        }
        // Drop the box only after the stream has been fully torn down so the
        // callback can never run with a dangling pointer.
        directoryStreamBox = nil

        continuation?.finish()
        continuation = nil
    }
}

/// Holds an immutable reference to the stream continuation so an opaque
/// `UnsafeMutableRawPointer` can be handed to `FSEventStreamCreate`'s C
/// context. `AsyncStream.Continuation` is already `Sendable`, so storing it
/// in a `let` makes the wrapping class trivially `Sendable` — no `@unchecked`
/// escape hatch needed.
private final class SendableContinuationBox: Sendable {
    let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation?

    init(continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation?) {
        self.continuation = continuation
    }
}
