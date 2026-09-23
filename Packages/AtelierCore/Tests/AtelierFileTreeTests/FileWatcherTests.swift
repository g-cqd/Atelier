import Foundation
import Testing

@testable import AtelierFileTree

@Suite(.tags(.fileWatcher))
struct FileWatcherTests {
    private enum RaceOutcome<Element: Sendable>: Sendable {
        case element(Element?)
        case timedOut
    }

    /// The next element of `stream`, or nil once `timeout` elapses, so a missed FSEvent fails the test instead of
    /// hanging the suite.
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

    /// A released watcher or a stopped stream must never leave FSEvents calling into freed state: the app crashed
    /// in the field with a callback yielding through a deallocated context box.
    @Test func `stopping or dropping watchers while their events are in flight never reaches freed state`()
        async throws
    {
        let tree = try TempTree()
        try tree.createFile(named: "churn.txt", content: "0")
        for round in 0 ..< 60 {
            let watcher = FileWatcher()
            await watcher.watchDirectory(tree.root)
            try "\(round)".write(toFile: tree.root + "/churn.txt", atomically: true, encoding: .utf8)
            // Even rounds stop explicitly; odd rounds drop the watcher and leave teardown to its deinit.
            if round.isMultiple(of: 2) { await watcher.stop() }
        }
        let survivor = FileWatcher()
        await survivor.watchDirectory(tree.root)
        try "done".write(toFile: tree.root + "/churn.txt", atomically: true, encoding: .utf8)
        #expect(await nextElement(of: survivor.events) != nil)
        await survivor.stop()
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
