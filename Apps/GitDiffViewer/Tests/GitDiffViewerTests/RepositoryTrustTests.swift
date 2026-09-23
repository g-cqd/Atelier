import AtelierLSP
import Foundation
import Testing

@testable import DiffComparison

/// Scratch directories that stand in for repositories, removed when the test releases them.
private final class ScratchDirectories {
    let parent: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory.appending(
            path: "gdv-trust-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    }

    func directory(_ name: String) throws -> URL {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    deinit { try? FileManager.default.removeItem(at: parent) }
}

@MainActor
struct RepositoryTrustTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.trust.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Answers the request a window would show next.
    private func answerNext(_ trust: RepositoryTrust, trusts: Bool) throws {
        trust.answer(try #require(trust.claimNextRequest()), trusts: trusts)
    }

    @Test
    func `a repository nobody decided on is untrusted`() throws {
        let scratch = try ScratchDirectories()
        let root = try scratch.directory("repository")
        let trust = RepositoryTrust(defaults: try makeDefaults())

        #expect(trust.decision(for: root) == nil)
        #expect(!trust.isTrusted(root))
        #expect(trust.trustedRoots.isEmpty)
    }

    @Test
    func `trusting a repository through a symbolic link trusts its real path`() throws {
        let scratch = try ScratchDirectories()
        let real = try scratch.directory("real")
        let link = scratch.parent.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let trust = RepositoryTrust(defaults: try makeDefaults())

        trust.requestTrust(for: link)
        #expect(trust.nextRequest?.root == SourceKitLSPRegistry.canonicalRoot(real))
        try answerNext(trust, trusts: true)

        #expect(trust.isTrusted(real))
        #expect(trust.isTrusted(link))
        #expect(trust.trustedRoots == [try #require(SourceKitLSPRegistry.canonicalRoot(real))])
    }

    @Test
    func `a hover asks about an unknown repository once, and never again once answered`() throws {
        let scratch = try ScratchDirectories()
        let root = try scratch.directory("repository")
        let trust = RepositoryTrust(defaults: try makeDefaults())

        trust.requestDecision(for: root)
        trust.requestDecision(for: root)
        let request = try #require(trust.claimNextRequest())
        trust.requestDecision(for: root)
        #expect(trust.claimNextRequest() == nil)

        trust.answer(request, trusts: false)
        trust.requestDecision(for: root)

        #expect(trust.decision(for: root) == .declined)
        #expect(trust.nextRequest == nil)
    }

    @Test
    func `an explicit request asks again about a declined repository, and never about a trusted one`() throws {
        let scratch = try ScratchDirectories()
        let declined = try scratch.directory("declined")
        let trusted = try scratch.directory("trusted")
        let trust = RepositoryTrust(defaults: try makeDefaults())
        trust.requestTrust(for: declined)
        try answerNext(trust, trusts: false)
        trust.requestTrust(for: trusted)
        try answerNext(trust, trusts: true)

        trust.requestTrust(for: trusted)
        #expect(trust.nextRequest == nil)
        trust.requestTrust(for: declined)
        #expect(trust.nextRequest?.root == SourceKitLSPRegistry.canonicalRoot(declined))
    }

    @Test
    func `a directory that does not exist is never asked about`() throws {
        let scratch = try ScratchDirectories()
        let missing = scratch.parent.appending(path: "missing", directoryHint: .isDirectory)
        let trust = RepositoryTrust(defaults: try makeDefaults())

        trust.requestDecision(for: missing)
        trust.requestTrust(for: missing)

        #expect(trust.nextRequest == nil)
        #expect(!trust.isTrusted(missing))
    }

    @Test
    func `one window shows a request at a time, and a released request waits for the next window`() throws {
        let scratch = try ScratchDirectories()
        let first = try scratch.directory("first")
        let second = try scratch.directory("second")
        let trust = RepositoryTrust(defaults: try makeDefaults())
        trust.requestDecision(for: first)
        trust.requestDecision(for: second)

        let shown = try #require(trust.claimNextRequest())
        #expect(shown.root == SourceKitLSPRegistry.canonicalRoot(first))
        #expect(trust.nextRequest == nil)
        #expect(trust.claimNextRequest() == nil)

        trust.release(shown)
        #expect(trust.claimNextRequest() == shown)
        trust.answer(shown, trusts: true)
        #expect(trust.nextRequest?.root == SourceKitLSPRegistry.canonicalRoot(second))
    }

    @Test
    func `decisions persist across launches`() throws {
        let scratch = try ScratchDirectories()
        let trusted = try scratch.directory("trusted")
        let declined = try scratch.directory("declined")
        let defaults = try makeDefaults()
        let trust = RepositoryTrust(defaults: defaults)
        trust.requestTrust(for: trusted)
        try answerNext(trust, trusts: true)
        trust.requestTrust(for: declined)
        try answerNext(trust, trusts: false)

        let relaunched = RepositoryTrust(defaults: defaults)

        #expect(relaunched.isTrusted(trusted))
        #expect(relaunched.decision(for: declined) == .declined)
    }

    @Test
    func `an unreadable stored decision reads as untrusted`() throws {
        let scratch = try ScratchDirectories()
        let root = try #require(SourceKitLSPRegistry.canonicalRoot(try scratch.directory("repository")))
        let defaults = try makeDefaults()
        defaults.set(
            [root.path(percentEncoded: false).trimmingSuffix("/"): "always"], forKey: RepositoryTrust.storageKey)

        let trust = RepositoryTrust(defaults: defaults)

        #expect(trust.decision(for: root) == nil)
    }

    @Test
    func `only a trusted repository allows Fetch`() throws {
        let scratch = try ScratchDirectories()
        let trusted = try scratch.directory("trusted")
        let declined = try scratch.directory("declined")
        let unknown = try scratch.directory("unknown")
        let trust = RepositoryTrust(defaults: try makeDefaults())
        trust.requestTrust(for: trusted)
        try answerNext(trust, trusts: true)
        trust.requestTrust(for: declined)
        try answerNext(trust, trusts: false)

        #expect(trust.allowsFetch(in: trusted))
        #expect(!trust.allowsFetch(in: declined))
        #expect(!trust.allowsFetch(in: unknown))
        #expect(!trust.allowsFetch(in: nil))
    }

    @Test
    func `revoking a trusted repository declines it and reports the change`() throws {
        let scratch = try ScratchDirectories()
        let root = try scratch.directory("repository")
        let trust = RepositoryTrust(defaults: try makeDefaults())
        trust.requestTrust(for: root)
        try answerNext(trust, trusts: true)
        var changes: [(URL, RepositoryTrust.Decision)] = []
        trust.onDecisionChanged = { changes.append(($0, $1)) }

        trust.revoke(root)
        trust.revoke(root)

        #expect(!trust.isTrusted(root))
        #expect(trust.decision(for: root) == .declined)
        #expect(trust.trustedRoots.isEmpty)
        #expect(changes.count == 1)
        #expect(changes.first?.0 == SourceKitLSPRegistry.canonicalRoot(root))
        #expect(changes.first?.1 == .declined)
    }
}

extension String {
    /// The string without `suffix` at its end, when it ends with it.
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
