package import DiffGit
package import Foundation
import Observation

/// The configuration keys the user allows per repository despite ``GitConfigPolicy``'s allowlist, kept in user
/// defaults and handed to the ``GitConfigGate`` every git command goes through. A key that names a program is never
/// stored: the gate would refuse it anyway.
@Observable
@MainActor
package final class RepositoryConfigurationAllowances {
    /// The defaults key: a dictionary from repository root path to its allowed keys.
    static let storageKey = "repositoryConfigurationAllowances"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let gate: GitConfigGate
    /// Allowed keys by root path, without a trailing slash.
    private var allowances: [String: [String]]

    /// Reads the stored allowances and hands each one to `gate`.
    package init(defaults: UserDefaults = .standard, gate: GitConfigGate = .shared) {
        self.defaults = defaults
        self.gate = gate
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: [String]] ?? [:]
        allowances = stored.mapValues { $0.filter(GitConfigPolicy.canBeAllowed) }.filter { !$0.value.isEmpty }
        for (path, keys) in allowances {
            gate.allow(Set(keys), inRepository: URL(filePath: path, directoryHint: .isDirectory))
        }
    }

    /// The keys allowed in the repository at `root`, sorted; empty when none are.
    package func allowedKeys(for root: URL) -> [String] {
        allowances[Self.key(of: root)] ?? []
    }

    /// Allows `keys` in the repository at `root`, replacing what it allowed before; an empty list removes the
    /// allowance. Keys that name a program are left out.
    package func setAllowedKeys(_ keys: [String], for root: URL) {
        let allowed = Set(keys.filter(GitConfigPolicy.canBeAllowed)).sorted()
        allowances[Self.key(of: root)] = allowed.isEmpty ? nil : allowed
        defaults.set(allowances, forKey: Self.storageKey)
        gate.allow(Set(allowed), inRepository: root)
    }

    /// `root`'s path without a trailing slash.
    private static func key(of root: URL) -> String {
        let path = root.standardizedFileURL.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
