import AtelierDiagnostics
import DiffCore
import Foundation
import Testing

@testable import DiffComparison

/// Settings and recents that Foundation's JSON coders wrote load unchanged, and what the app writes now still reads
/// back through Foundation's `JSONDecoder`. The keys are spelled out because they are what users' defaults hold.
@MainActor
@Suite(.mainActorLane)
struct DefaultsJSONCompatibilityTests {
    private let heuristics = DiffHeuristics(anchorsRareLines: true, slidesToIndentation: false, whitespace: .ignoreAll)
    private let toolLocations: [String: ToolLocation] = [
        "swiftlint": ToolLocation(
            isEnabled: false, customPath: "/opt/homebrew/bin/swiftlint", bookmark: Data([0, 1, 0xFE, 0xFF])),
        "swift-format": ToolLocation(customPath: "/Users/é x/bin/swift-format")
    ]
    private let lspServerLocations = ["sourcekit-lsp": ToolLocation(isEnabled: false, customPath: "/usr/bin/lsp")]
    private let recents: [LaunchConfiguration] = [
        .repository(URL(filePath: "/repos/a b/app", directoryHint: .isDirectory), leftRef: "main", rightRef: nil),
        .repository(URL(filePath: "/repos/app", directoryHint: .isDirectory), leftRef: "v2", rightRef: "v1"),
        .files(left: URL(filePath: "/a.swift"), right: URL(filePath: "/é/b.swift")),
        .patch(URL(filePath: "/tmp/a.patch"))
    ]
    private let scratchDefaults = ScratchDefaults(tag: "defaultsJSON")

    @Test
    func `settings Foundation's encoder wrote load unchanged`() throws {
        let defaults = scratchDefaults.defaults
        defaults.set(try JSONEncoder().encode(heuristics), forKey: "diffHeuristics")
        defaults.set(try JSONEncoder().encode(toolLocations), forKey: "diagnosticToolLocations")
        defaults.set(try JSONEncoder().encode(lspServerLocations), forKey: "lspServerLocations")

        let sut = ViewerSettings(defaults: defaults)

        #expect(sut.diffHeuristics == heuristics)
        #expect(sut.toolLocations[.swiftlint] == toolLocations["swiftlint"])
        #expect(sut.toolLocations[.swiftFormat] == toolLocations["swift-format"])
        #expect(sut.lspServerLocations == lspServerLocations)
    }

    @Test
    func `settings written now load in Foundation's decoder`() throws {
        let defaults = scratchDefaults.defaults
        let sut = ViewerSettings(defaults: defaults)

        sut.diffHeuristics = heuristics
        sut.toolLocations = [.swiftlint: try #require(toolLocations["swiftlint"])]
        sut.lspServerLocations = lspServerLocations

        let decoder = JSONDecoder()
        let storedHeuristics = try #require(defaults.data(forKey: "diffHeuristics"))
        let storedTools = try #require(defaults.data(forKey: "diagnosticToolLocations"))
        let storedServers = try #require(defaults.data(forKey: "lspServerLocations"))
        #expect(try decoder.decode(DiffHeuristics.self, from: storedHeuristics) == heuristics)
        #expect(
            try decoder.decode([String: ToolLocation].self, from: storedTools) == [
                "swiftlint": toolLocations["swiftlint"]
            ])
        #expect(try decoder.decode([String: ToolLocation].self, from: storedServers) == lspServerLocations)
    }

    @Test
    func `project overrides and the base values Foundation's encoder wrote load on adoption and on restore`() throws {
        let defaults = scratchDefaults.defaults
        let project = ProjectIdentity(root: URL(filePath: "/repos/app", directoryHint: .isDirectory))
        let overrideServers = ["sourcekit-lsp": ToolLocation(customPath: "/opt/lsp")]
        defaults.set(try JSONEncoder().encode(DiffHeuristics.none), forKey: "diffHeuristics")
        defaults.set(try JSONEncoder().encode(heuristics), forKey: "project.\(project.key).diffHeuristics")
        defaults.set(try JSONEncoder().encode(lspServerLocations), forKey: "lspServerLocations")
        defaults.set(try JSONEncoder().encode(overrideServers), forKey: "project.\(project.key).lspServerLocations")
        let sut = ViewerSettings(defaults: defaults)

        sut.adoptProject(project)
        #expect(sut.diffHeuristics == heuristics)
        #expect(sut.lspServerLocations == overrideServers)

        sut.restoreDefaults(.diff)
        sut.restoreDefaults(.tools)
        #expect(sut.diffHeuristics == .none)
        #expect(sut.lspServerLocations == lspServerLocations)
    }

    @Test
    func `recents Foundation's encoder wrote load unchanged`() throws {
        let defaults = scratchDefaults.defaults
        defaults.set(try JSONEncoder().encode(recents), forKey: "recentComparisons")

        #expect(RecentComparisons(defaults: defaults).entries == recents)
    }

    @Test
    func `recents written now load in Foundation's decoder`() throws {
        let defaults = scratchDefaults.defaults
        let sut = RecentComparisons(defaults: defaults)

        for configuration in recents.reversed() { sut.record(configuration) }

        let stored = try #require(defaults.data(forKey: "recentComparisons"))
        #expect(sut.entries == recents)
        #expect(try JSONDecoder().decode([LaunchConfiguration].self, from: stored) == recents)
    }

    @Test
    func `a stored recent whose URL does not parse leaves the list empty`() throws {
        let defaults = scratchDefaults.defaults
        defaults.set(
            Data(#"[{"patch":{"_0":"file:///tmp/a.patch"}},{"patch":{"_0":""}}]"#.utf8), forKey: "recentComparisons")

        #expect(RecentComparisons(defaults: defaults).entries.isEmpty)
    }
}
