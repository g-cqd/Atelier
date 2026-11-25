import DiffGit
import Foundation
import Testing

@testable import DiffComparison

@MainActor
@Suite(.mainActorLane)
struct RepositoryConfigurationAllowancesTests {
    private let scratchDefaults = ScratchDefaults(tag: "config-allowances")
    private static let root = URL(filePath: "/repo", directoryHint: .isDirectory)
    private static let toolKey = "project-hooks.trusted"

    @Test
    func `allowed keys are kept across launches`() {
        RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: GitConfigGate())
            .setAllowedKeys([Self.toolKey], for: Self.root)

        let relaunched = RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: GitConfigGate())

        #expect(relaunched.allowedKeys(for: Self.root) == [Self.toolKey])
    }

    @Test
    func `a key that names a program is never stored`() {
        let sut = RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: GitConfigGate())

        sut.setAllowedKeys([Self.toolKey, "core.askpass"], for: Self.root)

        #expect(sut.allowedKeys(for: Self.root) == [Self.toolKey])
    }

    @Test
    func `stored allowances reach the gate at launch`() async {
        RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: GitConfigGate())
            .setAllowedKeys([Self.toolKey], for: Self.root)
        let gate = GitConfigGate()

        _ = RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: gate)

        #expect(await Self.verdict(of: gate).isApproved)
    }

    @Test
    func `removing the allowance refuses the key again`() async {
        let gate = GitConfigGate()
        let sut = RepositoryConfigurationAllowances(defaults: scratchDefaults.defaults, gate: gate)
        sut.setAllowedKeys([Self.toolKey], for: Self.root)

        sut.setAllowedKeys([], for: Self.root)

        #expect(sut.allowedKeys(for: Self.root).isEmpty)
        #expect(await Self.verdict(of: gate).refusedKeys == [Self.toolKey])
    }

    /// The gate's verdict on a repository at ``root`` whose own configuration holds only ``toolKey``.
    private static func verdict(of gate: GitConfigGate) async -> GitConfigVerdict {
        let listing = Data("local\0file:/repo/.git/config\0\(toolKey)\ntrue\0".utf8)
        return await gate.verdict(in: root, isolation: .strict) { listing }
    }
}
