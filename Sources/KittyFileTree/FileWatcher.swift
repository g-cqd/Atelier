import Foundation

public actor FileWatcher {
    public enum FileWatchEvent: Sendable {
        case fileChanged(String)
        case directoryChanged(String)
    }

    private var fileSources: [String: DispatchSourceFileSystemObject] = [:]
    private var directoryStream: FSEventStreamRef?
    private var streamQueue: DispatchQueue?
    private var continuation: AsyncStream<FileWatchEvent>.Continuation?
    private var suppressTimestamps: [String: Date] = [:]

    private static let debounceInterval: TimeInterval = 0.1
    private static let suppressWindow: TimeInterval = 1.0

    nonisolated public let events: AsyncStream<FileWatchEvent>

    public init() {
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

        var context = FSEventStreamContext()
        let boxed = Unmanaged.passRetained(SendableContinuationBox(continuation: continuation))
            .toOpaque()
        context.info = boxed

        let paths = [path] as CFArray
        let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info, let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String]
                else { return }
                let box = Unmanaged<SendableContinuationBox>.fromOpaque(info).takeUnretainedValue()
                for i in 0..<numEvents {
                    box.continuation?.yield(.directoryChanged(paths[i]))
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
        let capturedSelf = self

        source.setEventHandler {
            Task {
                let suppressed = await capturedSelf.isSuppressed(capturedPath)
                if !suppressed {
                    capturedContinuation?.yield(.fileChanged(capturedPath))
                }
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

    public func suppressNotifications(for path: String) {
        suppressTimestamps[path] = Date()
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

        continuation?.finish()
        continuation = nil
    }

    private func isSuppressed(_ path: String) -> Bool {
        guard let timestamp = suppressTimestamps[path] else { return false }
        if Date().timeIntervalSince(timestamp) < Self.suppressWindow {
            return true
        }
        suppressTimestamps.removeValue(forKey: path)
        return false
    }
}

private final class SendableContinuationBox: @unchecked Sendable {
    let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation?

    init(continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation?) {
        self.continuation = continuation
    }
}
