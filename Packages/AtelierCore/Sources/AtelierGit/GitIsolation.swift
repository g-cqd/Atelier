public import AtelierProcess
import Foundation

/// How far a git run is kept from the caller's environment and from the repository's own configuration.
///
/// A repository can carry a hostile `.git/config` (hooks, `core.sshCommand`, `core.fsmonitor`, file-protocol
/// submodules) and the parent's environment can carry `GIT_*` overrides; ``strict`` refuses both, the way an
/// editor opening an unknown checkout should. ``inheriting`` keeps the caller's environment and only stops
/// prompts and optional locks, the way a viewer the user pointed at a repository of their own expects.
/// ``networking`` sits between the two, for commands that reach a remote.
///
/// Pins are the second layer only. The first one is ``GitConfigPolicy``, which reads the repository's own
/// configuration before any command runs and refuses the ones a pin cannot cover, such as a `filter` driver whose
/// name only the repository knows.
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

    /// The keys both isolations pin, whatever the command: the git security advisories' remote-code-execution
    /// vectors from an attacker-controlled `.git/config`, and the signing programs `log` and `show` would otherwise
    /// start. `protocol.allow=never` with `protocol.ext.allow=never` beside it, because a repository's own
    /// `protocol.ext.allow=always` is the more specific key and would win over the general one alone.
    /// `diff.autoRefreshIndex=false` because `GIT_OPTIONAL_LOCKS=0` does not stop a porcelain `git diff` against the
    /// working tree from rewriting the user's `.git/index` when stat data is stale, which takes `index.lock` under a
    /// `git add` or `git commit` the user runs at the same moment.
    private static let sharedConfigurationFlags: [String] = [
        "-c", "protocol.allow=never",
        "-c", "protocol.ext.allow=never",
        "-c", "protocol.file.allow=never",
        "-c", "core.fsmonitor=false",
        "-c", "core.hooksPath=/dev/null",
        "-c", "diff.external=",
        "-c", "core.pager=cat",
        "-c", "core.editor=false",
        "-c", "uploadpack.packObjectsHook=",
        "-c", "gpg.program=false",
        "-c", "gpg.ssh.program=false",
        "-c", "gpg.x509.program=false",
        "-c", "diff.autoRefreshIndex=false"
    ]

    /// ``sharedConfigurationFlags`` with `core.sshCommand` pinned to a program that cannot run: a read command
    /// never reaches a remote, so nothing needs `ssh`. Pinned rather than omitted, since an omitted key lets the
    /// repository's own `.git/config` choose the command.
    public static let strictConfigurationFlags: [String] =
        sharedConfigurationFlags + ["-c", "core.sshCommand=/usr/bin/false"]

    /// ``sharedConfigurationFlags`` with the transports a fetch may use opened, the plain `ssh` pinned so a fetch
    /// can authenticate, and every way a repository has of naming a command during a transfer closed. The reset of
    /// `credential.helper` drops the whole helper list, including the user's own; ``GitClient`` puts the helpers
    /// defined outside the repository back, so a private `https` remote still authenticates.
    public static let networkingConfigurationFlags: [String] =
        sharedConfigurationFlags + [
            "-c", "core.sshCommand=ssh",
            "-c", "protocol.https.allow=always",
            "-c", "protocol.ssh.allow=always",
            "-c", "credential.helper=",
            "-c", "core.askPass=",
            "-c", "core.gitProxy="
        ]
}
