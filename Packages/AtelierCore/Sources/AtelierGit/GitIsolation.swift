public import AtelierProcess
import Foundation

/// How far a git run is kept from the caller's environment and from the repository's own configuration.
///
/// A repository can carry a hostile `.git/config` (hooks, `core.sshCommand`, `core.fsmonitor`, file-protocol
/// submodules) and the parent's environment can carry `GIT_*` overrides; ``strict`` refuses both, the way an
/// editor opening an unknown checkout should. ``inheriting`` keeps the caller's environment and only stops
/// prompts and optional locks, the way a viewer the user pointed at a repository of their own expects.
/// ``networking`` sits between the two: a command that must reach a remote (`fetch`) needs the caller's `HOME`,
/// `SSH_AUTH_SOCK` and git credential configuration to authenticate, so it cannot scrub the environment the way
/// ``strict`` does, but it still pins every dangerous configuration key that does not stand in the way of a
/// legitimate transport.
public enum GitIsolation: Sendable, Hashable {
    case inheriting
    case strict
    /// For commands that must talk to a remote: keeps the caller's environment (so `SSH_AUTH_SOCK`, `HOME` and
    /// credential helpers work) while still refusing hooks, pagers, editors and `packObjectsHook`; never scrubs
    /// `core.sshCommand`, because that would break every SSH remote.
    case networking

    /// The variables the child sees: ``GitClient/hardeningEnvironment`` on top of the parent's, or the fixed
    /// whitelist alone.
    public var environment: ProcessSpec.Environment {
        switch self {
            case .inheriting, .networking:
                .inherited(overriding: GitClient.hardeningEnvironment)
            case .strict:
                .exactly(Self.scrubbedEnvironment.merging(GitClient.hardeningEnvironment) { current, _ in current })
        }
    }

    /// `-c key=value` flags put before every command; empty when inheriting, every ``strictConfigurationFlags``
    /// key but `core.sshCommand` when ``networking``.
    public var configurationFlags: [String] {
        switch self {
            case .inheriting: []
            case .strict: Self.strictConfigurationFlags
            case .networking: Self.networkingConfigurationFlags
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
        "-c", "core.hooksPath=/dev/null",
        "-c", "diff.external=",
        "-c", "core.pager=cat",
        "-c", "core.editor=false",
        "-c", "uploadpack.packObjectsHook="
    ]

    /// ``strictConfigurationFlags`` without the `-c core.sshCommand=...` pair: a networking run still needs the
    /// caller's real SSH transport to authenticate against a remote.
    public static let networkingConfigurationFlags: [String] = stride(
        from: 0, to: strictConfigurationFlags.count, by: 2
    )
    .filter { strictConfigurationFlags[$0 + 1] != "core.sshCommand=/usr/bin/false" }
    .flatMap { [strictConfigurationFlags[$0], strictConfigurationFlags[$0 + 1]] }
}
