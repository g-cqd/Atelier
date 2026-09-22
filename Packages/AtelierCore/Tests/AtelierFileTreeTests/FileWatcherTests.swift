import Foundation
import Testing

@testable import AtelierFileTree

@Suite(.tags(.fileWatcher))
struct FileWatcherTests {
    /// Awaits the next element of `stream`, racing it against a bounded timeout so a missed FSEvent
    /// fails the test instead of hanging the suite. This is event-driven (the winning branch is
    /// whichever suspension resumes first), not polling.
    private enum RaceOutcome<Element: Sendable>: Sendable {
        case element(Element?)
        case timedOut
    }

    private func nextElement<Element: Sendable>(
        of stream: AsyncStream<Element>, timeout: Duration = .seconds(10)
    ) async -> Element? {
        await withTaskGroup(of: RaceOutcome<Element>.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return .element(await iterator.next())
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            defer { group.cancelAll() }
            guard let first = await group.next() else { return nil }
            if case .element(let value) = first {
                return value
            }
            return nil
        }
    }

    @Test func `watching a directory surfaces an event when a file inside it changes`() async throws {
        let tree = try TempTree()
        try tree.createFile(named: "existing.txt", content: "before")

        let watcher = FileWatcher()
        await watcher.watchDirectory(tree.root)

        try "after".write(toFile: tree.root + "/new.txt", atomically: true, encoding: .utf8)

        let received = await nextElement(of: watcher.events)
        #expect(received != nil)

        await watcher.stop()
    }

    @Test func `watching a file surfaces an event when it is written`() async throws {
        let tree = try TempTree()
        try tree.createFile(named: "watched.txt", content: "before")
        let path = tree.root + "/watched.txt"

        let watcher = FileWatcher()
        await watcher.watchFile(path)

        try "after".write(toFile: path, atomically: true, encoding: .utf8)

        let received = await nextElement(of: watcher.events)
        #expect(received != nil)
        if case .fileChanged(let changedPath) = received {
            #expect(changedPath == path)
        } else {
            Issue.record("expected a fileChanged event, got \(String(describing: received))")
        }

        await watcher.stop()
    }

    @Test func `the event stream finishes after stop`() async {
        let watcher = FileWatcher()
        await watcher.stop()

        var iterator = watcher.events.makeAsyncIterator()
        let next = await iterator.next()

        #expect(next == nil)
    }
}

@Suite(.tags(.fileWatcher))
struct SuppressionWindowTests {
    @Test func `a path recorded inside the window reports suppressed`() {
        let window = FileWatcher.SuppressionWindow(window: .seconds(1))
        window.record("/a", now: .seconds(10))

        #expect(window.isSuppressed("/a", now: .seconds(10.5)))
    }

    @Test func `a path is no longer suppressed once the window elapses`() {
        let window = FileWatcher.SuppressionWindow(window: .seconds(1))
        window.record("/a", now: .seconds(10))

        #expect(!window.isSuppressed("/a", now: .seconds(11.5)))
    }

    @Test func `an unrecorded path is never suppressed`() {
        let window = FileWatcher.SuppressionWindow(window: .seconds(1))

        #expect(!window.isSuppressed("/never-recorded", now: .seconds(10)))
    }
}

extension Tag {
    @Tag static var fileWatcher: Self
}
