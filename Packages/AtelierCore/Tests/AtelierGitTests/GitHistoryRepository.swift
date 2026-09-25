import AemiRuntime
import AtelierProcess
import Foundation

@testable import AtelierGit

/// A repository in a temporary directory, built with the real git for the history tests, and a client over it.
struct GitHistoryRepository {
    let root: URL
    private let pool = BlockingOffloadPool(width: 2)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "atelier-history-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    func remove() {
        pool.shutdown()
        try? FileManager.default.removeItem(at: root)
    }

    /// A client with a verdict cache of its own, so no test sees another's.
    func client() -> GitClient {
        GitClient(
            repository: root, runner: HardenedProcessRunner(pool: pool), timeout: .seconds(30), gate: GitConfigGate())
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Stages everything and commits it with `message`, returning the new commit's id.
    @discardableResult
    func commit(_ message: String, allowingEmpty: Bool = false) throws -> String {
        try git("add", "-A")
        try git(["commit", "-q", "-m", message] + (allowingEmpty ? ["--allow-empty"] : []))
        return try head()
    }

    func head() throws -> String {
        try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git outside the client under test, with an identity and no signing, template or hooks, and returns its
    /// standard output; a failing run throws.
    @discardableResult
    func git(_ arguments: String...) throws -> String {
        try git(arguments)
    }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = GitClient.executable
        process.arguments =
            [
                "-c", "user.name=Tess Ter", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                "-c", "init.templateDir=", "-c", "core.hooksPath=/dev/null"
            ] + arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed("git \(arguments.joined(separator: " ")) exited \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
