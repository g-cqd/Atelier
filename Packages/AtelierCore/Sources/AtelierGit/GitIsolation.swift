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
    /// credential helpers work) while still refusing hooks, pagers, editors and `packObjectsHook`; pins
    /// `core.sshCommand` to the plain trusted `ssh` binary instead of scrubbing it, because a bare removal would
    /// leave the repository's own `.git/config` free to name an arbitrary command that `fetch` then executes.
    case networking

    /// The variables the child sees: ``GitClient/hardeningEnvironment`` on top of the parent's, the same but with
    /// repository-selection variables stripped for ``networking``, or the fixed whitelist alone for ``strict``.
    public var environment: ProcessSpec.Environment {
        switch self {
            case .inheriting:
                .inherited(overriding: GitClient.hardeningEnvironment)
            case .networking:
                .exactly(
                    ProcessInfo.processInfo.environment
                        .filter { !Self.repositorySelectionVariables.contains($0.key) }
                        .merging(GitClient.hardeningEnvironment) { _, override in override })
            case .strict:
                .exactly(Self.scrubbedEnvironment.merging(GitClient.hardeningEnvironment) { current, _ in current })
        }
    }

    /// `GIT_*` variables that redirect git away from discovering the repository from its working directory: a
    /// caller whose own process happens to run with one of these set (for instance because it is itself launched
    /// from inside another checkout) must not have ``networking`` silently fetch into, or read out of, a different
    /// repository than the one the command's `currentDirectory` names. Authentication variables (`HOME`,
    /// `SSH_AUTH_SOCK`, credential helpers, `PATH`) are deliberately left alone; only repository-selection is
    /// stripped.
    public static let repositorySelectionVariables: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_CEILING_DIRECTORIES"
    ]

    /// `-c key=value` flags put before every command; empty when inheriting, every ``strictConfigurationFlags``
    /// key when ``networking``, but with `core.sshCommand` pinned to the trusted `ssh` binary instead of the
    /// blocking value ``strict`` uses.
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

    /// ``strictConfigurationFlags`` with `-c core.sshCommand=/usr/bin/false` replaced by `-c core.sshCommand=ssh`:
    /// a networking run still needs the caller's real SSH transport to authenticate against a remote, but it must
    /// never let a repository-supplied `.git/config` win that key by leaving it unset — `-c` flags are placed
    /// before the subcommand on the command line, and git lets the last occurrence of a key win across `-c` and
    /// config-file settings combined, so an *omitted* `-c` here would let the repository's own `core.sshCommand`
    /// take effect instead of this pinned, trusted binary.
    public static let networkingConfigurationFlags: [String] = stride(
        from: 0, to: strictConfigurationFlags.count, by: 2
    )
    .flatMap { index -> [String] in
        let key = strictConfigurationFlags[index]
        let value = strictConfigurationFlags[index + 1]
        return [key, value == "core.sshCommand=/usr/bin/false" ? "core.sshCommand=ssh" : value]
    }
}
