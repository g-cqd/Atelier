import AtelierGit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import KittyFileTree
@testable import KittyGit

/// A git call the test holds open: the runner's handler parks in ``reply()`` until the test releases an output.
private struct HeldGitCall: Sendable {
    private let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private let outputs: AsyncStream<ProcessOutput>
    private let outputContinuation: AsyncStream<ProcessOutput>.Continuation

    init() {
        (entered, enteredContinuation) = AsyncStream.makeStream()
        (outputs, outputContinuation) = AsyncStream.makeStream()
    }

    /// Called by the runner's handler: tells the test the call started, then waits for the output it releases.
    func reply() async -> ProcessOutput {
        enteredContinuation.yield()
        for await output in outputs {
            return output
        }
        return .failure(1, error: "released without an output")
    }

    /// Returns once the runner's handler is parked in ``reply()``.
    func waitUntilEntered() async {
        for await _ in entered {
            return
        }
    }

    func release(_ output: ProcessOutput) {
        outputContinuation.yield(output)
    }
}

/// Joins NUL-terminated `status --porcelain=v2 -z` records the way git emits them.
private func porcelain(_ records: [String]) -> ProcessOutput {
    ProcessOutput(
        terminationStatus: 0, standardOutput: Data((records.joined(separator: "\u{0}") + "\u{0}").utf8),
        standardError: Data())
}

private let modifiedTrackedFile = "1 .M N... 100644 100644 100644 aaaa bbbb tracked.txt"

/// A refresh keeps the last good state when git fails, and neither an older refresh nor a base read that a newer
/// refresh outdated can overwrite what the newer one found.
@Suite
struct GitStatusProviderRefreshTests {
    @Test
    func `a failing git status keeps the statuses, the branch and the line decorations of the last good one`()
        async
    {
        let statusCalls = Mutex(0)
        let runner = FakeProcessRunner.gated { spec in
            guard spec.arguments.contains("--porcelain=v2") else { return .success("one\ntwo\n") }
            let call = statusCalls.withLock { calls in
                calls += 1
                return calls
            }
            guard call == 1 else { return .failure(128, error: "fatal: unable to read index") }
            return porcelain(["# branch.head main", modifiedTrackedFile, "? loose.txt"])
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()
        let before = await provider.lineDecorations(for: "/project/loose.txt", lines: ["x", "y"])

        await provider.refresh()

        #expect(provider.branchName == "main")
        #expect(provider.status(for: "/project/tracked.txt") == .modified)
        #expect(provider.status(for: "/project/loose.txt") == .untracked)
        #expect(provider.summary == FileStatusSummary(modified: 1, added: 0, untracked: 1, deleted: 0, conflicted: 0))
        let after = await provider.lineDecorations(for: "/project/loose.txt", lines: ["x", "y"])
        #expect(before.markers == [0: .untracked, 1: .untracked])
        #expect(after == before)
    }

    @Test
    func `a refresh that finishes after a newer one leaves the newer statuses in place`() async {
        let statusCalls = Mutex(0)
        let olderStatus = HeldGitCall()
        let runner = FakeProcessRunner.gated { spec in
            let call = statusCalls.withLock { calls in
                calls += 1
                return calls
            }
            guard call == 1 else { return porcelain(["# branch.head newer", modifiedTrackedFile]) }
            return await olderStatus.reply()
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)

        async let older: Void = provider.refresh()
        await olderStatus.waitUntilEntered()
        await provider.refresh()
        olderStatus.release(porcelain(["# branch.head older", "? loose.txt"]))
        await older

        #expect(provider.branchName == "newer")
        #expect(provider.status(for: "/project/tracked.txt") == .modified)
        #expect(provider.status(for: "/project/loose.txt") == nil)
    }

    @Test
    func `a base read that a refresh overtakes is not cached, so the next request reads the new HEAD`() async {
        let showCalls = Mutex(0)
        let olderBase = HeldGitCall()
        let runner = FakeProcessRunner.gated { spec in
            if spec.arguments.contains("--porcelain=v2") { return porcelain([modifiedTrackedFile]) }
            let call = showCalls.withLock { calls in
                calls += 1
                return calls
            }
            guard call == 1 else { return .success("new\n") }
            return await olderBase.reply()
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()

        async let overtaken = provider.lineDecorations(for: "/project/tracked.txt", lines: ["new", ""])
        await olderBase.waitUntilEntered()
        await provider.refresh()
        olderBase.release(.success("old\n"))
        _ = await overtaken

        let decorations = await provider.lineDecorations(for: "/project/tracked.txt", lines: ["new", ""])
        #expect(decorations.isEmpty)
        #expect(showCalls.withLock { $0 } == 2)
    }

    @Test
    func `a base requested after a refresh does not join a read the refresh overtook`() async {
        let showCalls = Mutex(0)
        let olderBase = HeldGitCall()
        let runner = FakeProcessRunner.gated { spec in
            if spec.arguments.contains("--porcelain=v2") { return porcelain([modifiedTrackedFile]) }
            let call = showCalls.withLock { calls in
                calls += 1
                return calls
            }
            guard call == 1 else { return .success("new\n") }
            return await olderBase.reply()
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()

        async let overtaken = provider.lineDecorations(for: "/project/tracked.txt", lines: ["new", ""])
        await olderBase.waitUntilEntered()
        await provider.refresh()
        async let current = provider.lineDecorations(for: "/project/tracked.txt", lines: ["new", ""])
        olderBase.release(.success("old\n"))

        #expect(await current.isEmpty)
        #expect(await overtaken.markers == [0: .modified])
    }
}
