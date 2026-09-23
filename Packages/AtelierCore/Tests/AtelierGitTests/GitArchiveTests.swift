import AemiRuntime
import AemiTestKit
import AtelierProcess
import Foundation
import Synchronization
import Testing

@testable import AtelierGit

/// ``GitClient/withExportedTree(_:including:_:)`` against the git on this machine: what an export holds, where it
/// lives and for how long, and that a tree whose attributes name a filter or `export-subst` runs nothing.
///
/// Every payload is a script that runs `touch`; nothing here reaches the network or writes outside its own temporary
/// directory.
@Suite(.serialized)
struct GitArchiveTests {
    private static let swiftAndYAML: @Sendable (String) -> Bool = { $0.hasSuffix(".swift") || $0.hasSuffix(".yml") }

    @Test
    func `an export holds the committed files the filter accepts and nothing else`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["Sources/A.swift": "let a = 1\n", ".swiftlint.yml": "rules: []\n", "README.md": "hello\n"])
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files == [".swiftlint.yml": "rules: []\n", "Sources/A.swift": "let a = 1\n"])
    }

    @Test
    func `the export folder is readable by the user alone`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["A.swift": "let a = 1\n"])
        let client = lab.client()

        let mode = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in
            try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
        }

        #expect(mode == 0o700)
    }

    @Test
    func `the export folder is gone once the body returns`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["A.swift": "let a = 1\n"])
        let client = lab.client()

        let folder = try await client.withExportedTree(
            try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML
        ) { $0 }

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test
    func `the export folder is gone when the body throws`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["A.swift": "let a = 1\n"])
        let client = lab.client()
        let seen = FolderBox()

        await #expect(throws: CancellationError.self) {
            try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML) {
                folder in
                seen.set(folder)
                throw CancellationError()
            }
        }

        let folder = try #require(seen.value)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test
    func `treeID names the tree of the ref`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["A.swift": "let a = 1\n"])

        let tree = try await lab.client().treeID(of: "HEAD")

        #expect(tree == (try lab.git("rev-parse", "HEAD^{tree}")))
    }

    // MARK: - Attributes run nothing and change nothing

    @Test
    func `a file under export-subst keeps its placeholder`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        let committed = "let id = \"$Format:%H$\"\nlet tag = \"$Format:%(describe)$\"\n"
        try lab.commit([".gitattributes": "*.swift export-subst\n", "A.swift": committed])
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files["A.swift"] == committed)
    }

    @Test
    func `a filter the user's configuration defines never runs when the tree's attributes name it`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit([".gitattributes": "*.swift filter=evil\n", "A.swift": "let a = 1\n"])
        let payload = try lab.payload("smudge")
        // The driver comes from outside the repository, as a user's own git-lfs does, so the gate approves the run.
        let client = lab.client(
            environment: [
                "GIT_CONFIG_COUNT": "2", "GIT_CONFIG_KEY_0": "filter.evil.smudge", "GIT_CONFIG_VALUE_0": payload,
                "GIT_CONFIG_KEY_1": "filter.evil.process", "GIT_CONFIG_VALUE_1": payload
            ])

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files["A.swift"] == "let a = 1\n")
        #expect(!lab.markerExists("smudge"))
    }

    @Test
    func `a repository whose own configuration names a filter exports nothing and runs nothing`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit([".gitattributes": "*.swift filter=evil\n", "A.swift": "let a = 1\n"])
        try lab.git("config", "filter.evil.smudge", try lab.payload("repository-smudge"))
        let client = lab.client()
        let ran = FolderBox()

        await #expect(throws: GitError.self) {
            try await client.withExportedTree("4b825dc642cb6eb9a060e54bf8d69288fbee4904", including: Self.swiftAndYAML)
            {
                ran.set($0)
            }
        }

        #expect(ran.value == nil)
        #expect(!lab.markerExists("repository-smudge"))
    }

    @Test
    func `export-ignore drops no file from the export`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit([".gitattributes": "B.swift export-ignore\n", "A.swift": "let a = 1\n", "B.swift": "let b = 2\n"]
        )
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files["B.swift"] == "let b = 2\n")
    }

    @Test
    func `a line ending attribute leaves the committed bytes alone`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit([".gitattributes": "*.swift text eol=crlf\n", "A.swift": "let a = 1\nlet b = 2\n"])
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files["A.swift"] == "let a = 1\nlet b = 2\n")
    }

    @Test
    func `a symbolic link in the tree is not written`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        try lab.commit(["A.swift": "let a = 1\n"])
        try FileManager.default.createSymbolicLink(
            atPath: lab.root.appending(path: "Link.swift").path, withDestinationPath: "/etc/hosts")
        try lab.git("add", "Link.swift")
        try lab.git("commit", "-q", "-m", "link")
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files.keys.sorted() == ["A.swift"])
    }

    @Test
    func `a path longer than a tar name field is written in full`() async throws {
        let lab = try ArchiveLab()
        defer { lab.cleanup() }
        // Longer than a ustar prefix and name together, so git writes it in a pax header.
        let path = (1 ... 24).map { "directory\($0)" }.joined(separator: "/") + "/AVeryLongFileNameIndeed.swift"
        #expect(path.utf8.count > 256)
        try lab.commit([path: "let deep = true\n"])
        let client = lab.client()

        let files = try await client.withExportedTree(try await client.treeID(of: "HEAD"), including: Self.swiftAndYAML)
        { folder in try ArchiveLab.files(under: folder) }

        #expect(files[path] == "let deep = true\n")
    }

    // MARK: - The tar reader

    @Test
    func `a tar entry whose path climbs out of the folder is refused`() throws {
        let folder = try GitClient.makePrivateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(throws: TarExtractor.Failure.unsafePath("../escape.swift")) {
            try TarExtractor.extract(ArchiveLab.tar(entryNamed: "../escape.swift", contents: "x"), into: folder)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: folder.deletingLastPathComponent().appending(path: "escape.swift").path))
    }

    @Test
    func `the driver names of every filter key are read from a name listing`() {
        let listing = Data("core.bare\0filter.lfs.clean\0filter.lfs.smudge\0filter.a.b.process\0filter.x\0".utf8)

        #expect(GitClient.filterDrivers(inNameListing: listing) == ["lfs", "a.b"])
    }
}

/// A folder seen inside a closure, read after it.
private final class FolderBox: Sendable {
    private let folder = Mutex<URL?>(nil)

    var value: URL? { folder.withLock { $0 } }

    func set(_ folder: URL) { self.folder.withLock { $0 = folder } }
}

/// A repository built on disk with the real git, plus the payload scripts and markers of one vector.
private struct ArchiveLab {
    let directory: TemporaryDirectory
    let root: URL
    private let pool: BlockingOffloadPool

    init() throws {
        directory = TemporaryDirectory(prefix: "atelier-archive")
        root = URL(filePath: directory.file("repo"), directoryHint: .isDirectory)
        pool = BlockingOffloadPool(width: 2)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git("init", "-q", "-b", "main")
    }

    func cleanup() {
        pool.shutdown()
        directory.cleanup()
    }

    /// A client over this repository with a verdict cache of its own, `environment` added to every git run the way a
    /// user's shell or login configuration adds variables.
    func client(environment: [String: String] = [:]) -> GitClient {
        GitClient(
            repository: root,
            runner: EnvironmentAddingRunner(base: HardenedProcessRunner(pool: pool), variables: environment),
            timeout: .seconds(30), gate: GitConfigGate())
    }

    /// Writes `files` and commits them all.
    func commit(_ files: [String: String]) throws {
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try git("add", "-A")
        try git("commit", "-q", "-m", "files")
    }

    /// Runs git outside the client under test, with an identity, no signing and no template hooks.
    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = GitClient.executable
        process.arguments =
            ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "init.templateDir="]
            + arguments
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An executable script that leaves ``marker(_:)`` behind when it runs.
    func payload(_ name: String) throws -> String {
        let path = directory.file("payload-\(name).sh")
        try "#!/bin/sh\ntouch '\(marker(name))'\ncat\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }

    func marker(_ name: String) -> String { directory.file("marker-\(name)") }

    func markerExists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: marker(name)) }

    /// Every regular file under `folder`, relative path to contents.
    static func files(under folder: URL) throws -> [String: String] {
        var files: [String: String] = [:]
        for subpath in try FileManager.default.subpathsOfDirectory(atPath: folder.path) {
            let url = folder.appending(path: subpath)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files[subpath] = try String(contentsOf: url, encoding: .utf8)
        }
        return files
    }

    /// A one-entry ustar archive naming its file `name`, as a hostile stream could.
    static func tar(entryNamed name: String, contents: String) -> Data {
        var header = [UInt8](repeating: 0, count: 512)
        header.replaceSubrange(0 ..< name.utf8.count, with: Array(name.utf8))
        let size = Array(String(contents.utf8.count, radix: 8).utf8)
        header.replaceSubrange((124 + 11 - size.count) ..< (124 + 11), with: size)
        header[156] = UInt8(ascii: "0")
        header.replaceSubrange(257 ..< 263, with: Array("ustar\0".utf8))
        var body = Array(contents.utf8)
        body += [UInt8](repeating: 0, count: (512 - body.count % 512) % 512)
        return Data(header + body + [UInt8](repeating: 0, count: 1024))
    }
}

/// Adds `variables` to the environment of every run of `base`.
private struct EnvironmentAddingRunner: ProcessRunner {
    let base: any ProcessRunner
    let variables: [String: String]

    func run(_ spec: ProcessSpec) async throws -> ProcessOutput {
        var spec = spec
        switch spec.environment {
            case .exactly(let current):
                spec.environment = .exactly(current.merging(variables) { _, added in added })
            case .inherited(let overrides):
                spec.environment = .inherited(overriding: overrides.merging(variables) { _, added in added })
        }
        return try await base.run(spec)
    }
}
