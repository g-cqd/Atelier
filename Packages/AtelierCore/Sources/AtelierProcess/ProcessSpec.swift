public import Foundation

/// One subprocess to run: what, where, with which environment and input, and for how long at most.
public struct ProcessSpec: Sendable, Hashable {
    /// How the child's environment is built.
    public enum Environment: Sendable, Hashable {
        /// The parent's environment, as `Process` inherits it.
        case inherited
        /// Exactly these variables and nothing else; the parent's environment does not leak through.
        case exactly([String: String])
    }

    public var executable: URL
    public var arguments: [String]
    public var currentDirectory: URL?
    public var environment: Environment
    /// Bytes written to the child's standard input before it can read; nil closes the input at once.
    public var standardInput: Data?
    /// Wall-clock budget on the runner's clock; the child is terminated when it elapses.
    public var timeout: Duration?

    public init(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: Environment = .inherited,
        standardInput: Data? = nil,
        timeout: Duration? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
    }
}

/// What a finished child left behind.
public struct ProcessOutput: Sendable, Equatable {
    public let terminationStatus: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// True for a zero exit status.
    public var succeeded: Bool { terminationStatus == 0 }

    /// Standard error decoded as UTF-8 with surrounding whitespace removed, for messages.
    public var errorText: String {
        String(decoding: standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Why a run produced no output.
public enum ProcessError: Error, Equatable, Sendable {
    /// The child could not be started; the message comes from `Process.run()`.
    case launchFailed(String)
    /// The spec's timeout elapsed; the child was terminated.
    case timedOut(Duration)
    /// The runner's blocking pool refused the job.
    case poolUnavailable(String)
}

/// Runs subprocesses. The one seam tests substitute: a fake records the specs it receives and answers from a script.
public protocol ProcessRunner: Sendable {
    /// Runs `spec` to completion and returns everything it produced, whatever its exit status.
    /// - Throws: ``ProcessError`` when the child could not run to completion, or `CancellationError` when the calling
    ///   task was cancelled; the child is terminated in both cases.
    func run(_ spec: ProcessSpec) async throws -> ProcessOutput
}
