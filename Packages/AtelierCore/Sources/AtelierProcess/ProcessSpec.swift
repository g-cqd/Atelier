public import Foundation

/// One subprocess to run: what, where, with which environment and input, and for how long at most.
public struct ProcessSpec: Sendable, Hashable {
    /// How the child's environment is built.
    public enum Environment: Sendable, Hashable {
        /// The parent's environment as `Process` inherits it, with `overriding` set on top of it.
        case inherited(overriding: [String: String] = [:])
        /// Exactly these variables and nothing else; the parent's environment does not leak through.
        case exactly([String: String])

        /// The variables the child is given, or nil for the parent's environment untouched.
        public var variables: [String: String]? {
            switch self {
                case .inherited(let overrides) where overrides.isEmpty:
                    nil
                case .inherited(let overrides):
                    ProcessInfo.processInfo.environment.merging(overrides) { _, override in override }
                case .exactly(let variables):
                    variables
            }
        }
    }

    public var executable: URL
    public var arguments: [String]
    public var currentDirectory: URL?
    public var environment: Environment
    /// Bytes written to the child's standard input before it can read; nil closes the input at once.
    public var standardInput: Data?
    /// Wall-clock budget on the runner's clock; the child is terminated when it elapses.
    public var timeout: Duration?
    /// The most bytes of standard output a run takes; a child that writes more is terminated, and the run fails with
    /// ``ProcessError/outputLimitExceeded(_:limit:)``.
    public var standardOutputLimit: Int
    /// The most bytes of standard error a run takes, with the same consequence.
    public var standardErrorLimit: Int

    /// 512 MiB, git's own big-file threshold: far past any listing, log or blob batch the apps read, short of what a
    /// runaway child fills memory with.
    public static let defaultStandardOutputLimit = 512 << 20
    /// 16 MiB: room for a linter's progress lines over a large corpus.
    public static let defaultStandardErrorLimit = 16 << 20

    public init(
        executable: URL,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: Environment = .inherited(),
        standardInput: Data? = nil,
        timeout: Duration? = nil,
        standardOutputLimit: Int = Self.defaultStandardOutputLimit,
        standardErrorLimit: Int = Self.defaultStandardErrorLimit
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
        self.standardOutputLimit = standardOutputLimit
        self.standardErrorLimit = standardErrorLimit
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

    /// One of a child's two outputs.
    public enum Stream: Sendable, Hashable {
        case standardOutput
        case standardError
    }
}

/// Why a run produced no output.
public enum ProcessError: Error, Equatable, Sendable {
    /// The child could not be started; the message comes from `Process.run()`.
    case launchFailed(String)
    /// The spec's timeout elapsed; the child was terminated.
    case timedOut(Duration)
    /// The child wrote more than the spec's limit on one of its outputs; it was terminated and its output dropped.
    case outputLimitExceeded(ProcessOutput.Stream, limit: Int)
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
