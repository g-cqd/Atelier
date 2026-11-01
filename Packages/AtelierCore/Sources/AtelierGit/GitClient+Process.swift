internal import AtelierProcess
internal import Foundation
import func AemiRuntime.mapConcurrently

// Running git: its approved configuration, mitigation flags and the process itself; apart from the type's file, to
// keep its type body within the 300 lines SwiftLint allows.
extension GitClient {
    /// Runs git once the repository's configuration has been approved, and returns its standard output.
    /// - Throws: ``GitError/refusedConfiguration(_:)`` before git runs when the configuration is refused; otherwise
    ///   as ``spawn(_:input:in:runner:timeout:isolation:extraConfiguration:)``.
    static func run(
        _ arguments: [String],
        input: Data? = nil,
        in directory: URL,
        runner: any ProcessRunner,
        timeout: Duration? = nil,
        isolation: GitIsolation = .strict,
        gate: GitConfigGate = .shared
    ) async throws -> Data {
        let verdict = try await approvedConfiguration(
            in: directory,
            runner: runner,
            timeout: timeout,
            isolation: isolation,
            gate: gate
        )
        return try await spawn(
            arguments,
            input: input,
            in: directory,
            runner: runner,
            timeout: timeout,
            isolation: isolation,
            extraConfiguration: mitigationFlags(for: verdict, isolation: isolation)
        )
    }

    /// The repository's configuration verdict, read through `gate` and cached there.
    /// - Throws: ``GitError/refusedConfiguration(_:)`` when a key falls outside ``GitConfigPolicy``'s allowlist, so
    ///   that no command runs in that repository at all.
    static func approvedConfiguration(
        in directory: URL,
        runner: any ProcessRunner,
        timeout: Duration?,
        isolation: GitIsolation,
        gate: GitConfigGate
    ) async throws -> GitConfigVerdict {
        let verdict = try await gate.verdict(in: directory, isolation: isolation) {
            try await spawn(
                GitConfigPolicy.listingArguments,
                in: directory,
                runner: runner,
                timeout: timeout,
                isolation: isolation
            )
        }
        guard verdict.isApproved else { throw GitError.refusedConfiguration(verdict.refusedKeys) }
        return verdict
    }

    /// The `-c` flags one repository's verdict adds to its commands: every filter driver it defines blanked, and,
    /// for a fetch, the credential helpers defined outside the repository put back after the pins reset the list.
    static func mitigationFlags(for verdict: GitConfigVerdict, isolation: GitIsolation) -> [String] {
        var flags = GitConfigPolicy.filterBlankingFlags(for: verdict.filterDrivers)
        if isolation == .networking {
            flags += verdict.userCredentialHelpers.flatMap { ["-c", "credential.helper=\($0)"] }
        }
        return flags
    }

    /// Runs git and returns its standard output; a non-zero exit becomes a ``GitError`` carrying its standard error,
    /// a runner failure becomes a ``GitError`` naming it, and cancelling the task terminates git.
    static func spawn(
        _ arguments: [String],
        input: Data? = nil,
        in directory: URL,
        runner: any ProcessRunner,
        timeout: Duration? = nil,
        isolation: GitIsolation = .strict,
        extraConfiguration: [String] = []
    ) async throws -> Data {
        let output = try await execute(
            arguments,
            input: input,
            in: directory,
            runner: runner,
            timeout: timeout,
            isolation: isolation,
            extraConfiguration: extraConfiguration
        )
        guard output.succeeded else { throw GitError.commandFailed(output.errorText) }
        return output.standardOutput
    }

    /// Runs git with the isolation's flags and environment and returns how it exited, for the caller to judge; a
    /// runner failure becomes a ``GitError`` naming it, and cancelling the task terminates git.
    static func execute(
        _ arguments: [String],
        input: Data? = nil,
        in directory: URL,
        runner: any ProcessRunner,
        timeout: Duration? = nil,
        isolation: GitIsolation = .strict,
        extraConfiguration: [String] = []
    ) async throws -> ProcessOutput {
        PhaseTrace.log("git \(arguments.prefix(2).joined(separator: " "))")
        defer { PhaseTrace.log("git done \(arguments.prefix(2).joined(separator: " "))") }
        let spec = ProcessSpec(
            executable: executable,
            arguments: isolation.configurationFlags + extraConfiguration + arguments,
            currentDirectory: directory,
            environment: isolation.environment,
            standardInput: input,
            timeout: timeout
        )
        do {
            return try await runner.run(spec)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw GitError.commandFailed("could not run git: \(error)")
        }
    }
}
