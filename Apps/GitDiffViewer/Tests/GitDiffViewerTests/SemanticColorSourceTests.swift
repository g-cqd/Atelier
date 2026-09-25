import AtelierLSP
import AtelierSyntaxModel
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// Which Swift sides ask sourcekit-lsp for semantic colour (PERF-11 step 8): only the right side's files on disk, with
/// the setting on.
@MainActor
@Suite(.mainActorLane)
struct SemanticColorSourceTests {
    /// The roots a registry was asked to configure a session at; it resolves none, so no server runs.
    private final class ConfigurationLog: Sendable {
        private let roots = Mutex<[URL]>([])

        var all: [URL] { roots.withLock { $0 } }

        func registry() -> LanguageServerRegistry {
            LanguageServerRegistry(
                admits: { _, _ in true },
                makeConfiguration: { root, _ in
                    self.roots.withLock { $0.append(root) }
                    return nil
                })
        }
    }

    private let scratchDefaults = ScratchDefaults(tag: "semanticColor")
    private static let path = "Sources/A.swift"
    private static let entries = [SourceEntry(relativePath: path, blobID: "new", size: 12)]

    private static func revision(_ blob: String) -> SourceRevision {
        SourceRevision(documentID: path, language: .swift, key: .content(blob))
    }

    /// A source reading `shownRight`, the right side's files ``entries``, over a registry that records into `log`.
    private func makeSource(
        shownRight: ComparisonSource?, log: ConfigurationLog, enabled: Bool = true
    ) -> SemanticColorSource {
        let source = SemanticColorSource()
        source.registry = log.registry()
        source.isEnabled = enabled
        source.readShownRight { (shownRight, Self.entries) }
        return source
    }

    private func makeRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gdv-semantic-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func `a side on disk asks for sourcekit-lsp's session at its repository`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ConfigurationLog()
        let source = makeSource(shownRight: .directory(root), log: log)
        let canonical = try #require(LanguageServerRegistry.canonicalRoot(root))

        _ = await source.document(for: Self.revision("new"))

        #expect(log.all == [canonical])
        let location = SemanticColorSource.onDiskLocation(
            of: Self.revision("new"), shownRight: .directory(root), entries: Self.entries)
        #expect(location?.document == canonical.appending(path: Self.path))
    }

    @Test
    func `with the setting off, no side asks`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ConfigurationLog()
        let source = makeSource(shownRight: .directory(root), log: log, enabled: false)

        #expect(await source.document(for: Self.revision("new")) == nil)
        #expect(log.all.isEmpty)
    }

    @Test
    func `a side from history, and a commit's own change, never ask`() async throws {
        let root = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ConfigurationLog()
        let working = makeSource(shownRight: .directory(root), log: log)
        let commit = makeSource(shownRight: .gitRef(repository: root, ref: "abc123"), log: log)

        // The old side's blob, which no file on disk holds.
        #expect(await working.document(for: Self.revision("old")) == nil)
        #expect(await commit.document(for: Self.revision("new")) == nil)
        #expect(log.all.isEmpty)
    }

    @Test
    func `the setting is on by default, applies to every project, and restores to on`() {
        let settings = ViewerSettings(defaults: scratchDefaults.defaults)
        #expect(settings.semanticColor)
        #expect(!ViewerSettings.isProjectScoped(\ViewerSettings.semanticColor))

        settings.semanticColor = false
        #expect(!ViewerSettings(defaults: scratchDefaults.defaults).semanticColor)
        settings.restoreDefaults(.appearance)
        #expect(settings.semanticColor)
    }
}
