import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

@MainActor
struct RecentComparisonsTests {
    private let repository = URL(filePath: "/repos/app", directoryHint: .isDirectory)

    @Test
    func `entries are newest first, one per target, capped, and persisted`() throws {
        let defaults = try makeDefaults()
        let sut = RecentComparisons(defaults: defaults)

        sut.record(.repository(repository, leftRef: "main", rightRef: nil))
        sut.record(.patch(URL(filePath: "/tmp/a.patch")))
        sut.record(.repository(repository, leftRef: "feature", rightRef: "main"))
        for index in 0 ..< RecentComparisons.limit {
            sut.record(.files(left: URL(filePath: "/l\(index)"), right: URL(filePath: "/r\(index)")))
        }

        #expect(sut.entries.count == RecentComparisons.limit)
        #expect(
            sut.entries.first
                == .files(
                    left: URL(filePath: "/l\(RecentComparisons.limit - 1)"),
                    right: URL(filePath: "/r\(RecentComparisons.limit - 1)")))
        #expect(!sut.entries.contains(.repository(repository, leftRef: "main", rightRef: nil)))

        let reloaded = RecentComparisons(defaults: defaults)
        #expect(reloaded.entries == sut.entries)
    }

    @Test
    func `a repository opened again with other refs replaces its entry at the top`() throws {
        let sut = RecentComparisons(defaults: try makeDefaults())
        sut.record(.repository(repository, leftRef: "main", rightRef: nil))
        sut.record(.patch(URL(filePath: "/tmp/a.patch")))

        sut.record(.repository(repository, leftRef: "v2", rightRef: "v1"))

        #expect(
            sut.entries == [
                .repository(repository, leftRef: "v2", rightRef: "v1"), .patch(URL(filePath: "/tmp/a.patch"))
            ])

        sut.remove(.patch(URL(filePath: "/tmp/a.patch")))
        #expect(sut.entries.count == 1)
        sut.clear()
        #expect(sut.entries.isEmpty)
    }

    @Test
    func `a configuration round trips through JSON`() throws {
        let configurations: [LaunchConfiguration] = [
            .repository(repository, leftRef: "main", rightRef: nil),
            .files(left: URL(filePath: "/a.swift"), right: URL(filePath: "/b.swift")),
            .patch(URL(filePath: "/tmp/a.patch"))
        ]
        let data = try JSONEncoder().encode(configurations)
        #expect(try JSONDecoder().decode([LaunchConfiguration].self, from: data) == configurations)
    }

    @Test
    func `settings changes reach every observer still alive`() throws {
        let settings = ViewerSettings(defaults: try makeDefaults())
        final class Owner {}
        var owner: Owner? = Owner()
        let kept = Owner()
        var received: [ViewerSettings.Change] = []
        settings.addObserver(owner!) { received.append($0) }
        settings.addObserver(kept) { received.append($0) }

        settings.showsMinimap = false
        #expect(received == [.appearance, .appearance])

        owner = nil
        settings.showsMinimap = true
        #expect(received == [.appearance, .appearance, .appearance])
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.recents.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
