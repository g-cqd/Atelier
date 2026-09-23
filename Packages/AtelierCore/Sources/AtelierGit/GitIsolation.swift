public import AtelierProcess
import Foundation

/// How far a git run is kept from the caller's environment and from the repository's own configuration.
///
/// A repository can carry a hostile `.git/config` (hooks, `core.sshCommand`, `core.fsmonitor`, file-protocol
/// submodules) and the parent's environment can carry `GIT_*` overrides; ``strict`` refuses both, the way an
/// editor opening an unknown checkout should. ``inheriting`` keeps the caller's environment and only stops
/// prompts and optional locks, the way a viewer the user pointed at a repository of their own expects.
/// ``networking`` sits between the two, for commands that reach a remote.
public enum GitIsolation: Sendable, Hashable {
    case inheriting
    case strict
    /// The caller's environment without repository-selection variables, so `HOME`, `SSH_AUTH_SOCK` and credential
    /// helpers work, and the strict configuration pins with `core.sshCommand` set to the plain `ssh`.
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

    /// `GIT_*` variables that redirect git away from the repository its working directory names; ``networking``
    /// strips them so an inherited one cannot point `fetch` at a different repository.
    public static let repositorySelectionVariables: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_NAMESPACE", "GIT_CEILING_DIRECTORIES"
    ]

    /// `-c key=value` flags put before every command; empty when inheriting.
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

    /// ``strictConfigurationFlags`` with `core.sshCommand` pinned to the plain `ssh` so a fetch can authenticate;
    /// pinned rather than omitted, since an omitted key lets the repository's own `.git/config` choose the command.
    public static let networkingConfigurationFlags: [String] = stride(
        from: 0, to: strictConfigurationFlags.count, by: 2
    )
    .flatMap { index -> [String] in
        let key = strictConfigurationFlags[index]
        let value = strictConfigurationFlags[index + 1]
        return [key, value == "core.sshCommand=/usr/bin/false" ? "core.sshCommand=ssh" : value]
    }
}
