import AtelierGit
import Foundation

@testable import AtelierSources

/// A repository in a temporary directory, built with the real git, for the tests that compare a working tree with a
/// ref the way the app's default comparison does.
struct SourceRepository {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "atelier-sources-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ relativePath: String, _ contents: String) throws {
        try write(relativePath, Data(contents.utf8))
    }

    func write(_ relativePath: String, _ data: Data) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func link(_ relativePath: String, to target: String) throws {
        let path = root.appending(path: relativePath).path(percentEncoded: false)
        try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
    }

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: root.appending(path: relativePath))
    }

    /// Stages everything and commits it.
    func commit(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }

    /// Runs git outside the code under test, with an identity and no signing, template or hooks, and returns its
    /// standard output; a failing run throws.
    @discardableResult
    func git(_ arguments: String...) throws -> String {
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

    /// Each path's blob id, HEAD's and the working tree's, as the default comparison lists them.
    func headAndWorkingTree(
        loader: SourceLoader = TestProcesses.loader
    ) async throws -> (head: [String: String?], workingTree: [String: String?]) {
        func ids(_ entries: [GitTreeEntry]) -> [String: String?] {
            Dictionary(entries.map { ($0.relativePath, $0.blobID) }, uniquingKeysWith: { first, _ in first })
        }
        let head = try await loader.entries(of: .gitRef(repository: root, ref: "HEAD"))
        let workingTree = try await loader.entries(of: .directory(root))
        return (ids(head), ids(workingTree))
    }
}
