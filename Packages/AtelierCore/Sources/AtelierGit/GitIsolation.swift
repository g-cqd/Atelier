public import AtelierProcess
import Foundation

/// How far a git run is kept from the caller's environment and from the repository's own configuration.
///
/// A repository can carry a hostile `.git/config` (hooks, `core.sshCommand`, `core.fsmonitor`, file-protocol
/// submodules) and the parent's environment can carry `GIT_*` overrides; ``strict`` refuses both, the way an
/// editor opening an unknown checkout should. ``inheriting`` keeps the caller's environment and only stops
/// prompts and optional locks, the way a viewer the user pointed at a repository of their own expects.
public enum GitIsolation: Sendable, Hashable {
    case inheriting
    case strict

    /// The variables the child sees: ``GitClient/hardeningEnvironment`` on top of the parent's, or the fixed
    /// whitelist alone.
    public var environment: ProcessSpec.Environment {
        switch self {
            case .inheriting:
                .inherited(overriding: GitClient.hardeningEnvironment)
            case .strict:
                .exactly(Self.scrubbedEnvironment.merging(GitClient.hardeningEnvironment) { current, _ in current })
        }
    }

    /// `-c key=value` flags put before every command; empty when inheriting.
    public var configurationFlags: [String] {
        switch self {
            case .inheriting: []
            case .strict: Self.strictConfigurationFlags
        }
    }

    /// A fixed `PATH` so no `~/bin/git` shadows the tool, `C` locale for stable output, `HOME` for the user's own
    /// git configuration, and no system-wide configuration a shared host could plant.
    public static let scrubbedEnvironment: [String: String] = [
        "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
        "LANG": "C",
        "LC_ALL": "C",
        "HOME": NSHomeDirectory(),
        "GIT_CONFIG_NOSYSTEM": "1"
    ]

    /// The configuration keys git security advisories name as remote-code-execution vectors from an
    /// attacker-controlled `.git/config`, pinned to safe values; no workspace setting can re-enable them.
    public static let strictConfigurationFlags: [String] = [
        "-c", "protocol.file.allow=user",
        "-c", "core.fsmonitor=false",
        "-c", "core.sshCommand=/usr/bin/false",
        "-c", "core.hooksPath=/dev/null"
    ]
}
