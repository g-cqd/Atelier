import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// The suites the tests write leave nothing on disk. cfprefsd writes a suite's changes lazily, seconds after them, and
/// puts a plist deleted in between back, so the only plist that cannot come back to the user's preferences is one
/// that never went there: these check where a scratch suite's plist goes, and that nothing of it is left once the
/// suite, or the harness that holds it for its models, is released.
@MainActor
@Suite(.mainActorLane)
struct ScratchDefaultsTests {
    private nonisolated static let preferences = URL.libraryDirectory.appending(
        path: "Preferences", directoryHint: .isDirectory)

    @Test
    func `a scratch suite keeps its plist out of the user's preferences`() async throws {
        let scratch = ScratchDefaults(tag: "kept")

        scratch.defaults.set(true, forKey: "written")

        let inPreferences = try await Self.entries(in: Self.preferences, containing: scratch.name)
        #expect(FileManager.default.fileExists(atPath: scratch.plist.path(percentEncoded: false)))
        #expect(inPreferences == [])
    }

    @Test
    func `a released scratch suite leaves no plist of its name behind`() async throws {
        var scratch: ScratchDefaults? = ScratchDefaults(tag: "released")
        let name = try #require(scratch?.name)
        let plist = try #require(scratch?.plist)
        scratch?.defaults.set(true, forKey: "written")
        // A suite's first write reaches the disk at once, so there is a plist to leave behind.
        try #require(FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))

        scratch = nil

        let leftovers = try await Self.leftovers(of: name)
        #expect(!FileManager.default.fileExists(atPath: plist.path(percentEncoded: false)))
        #expect(leftovers == [])
    }

    @Test
    func `a model run leaves none of its settings on disk once its harness is released`() async throws {
        let name = try await runModel()

        let leftovers = try await Self.leftovers(of: name)
        #expect(leftovers == [])
    }

    /// Loads a comparison into a harness's model and changes two of its settings, as the model suites do, then lets
    /// the harness and the model go. Returns the name of the suite the settings were written to.
    private func runModel() async throws -> String {
        let harness = ModelTestHarness()
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)

        sut.settings.showsChangesOnly = true
        sut.settings.contextLines = 5
        try await harness.taskProvider.waitForAllTasks()

        try #require(FileManager.default.fileExists(atPath: harness.scratchDefaults.plist.path(percentEncoded: false)))
        return harness.scratchDefaults.name
    }

    /// Everything named after `name` in the user's preferences or in the temporary directory.
    private nonisolated static func leftovers(of name: String) async throws -> [String] {
        try await entries(in: preferences, containing: name)
            + entries(in: FileManager.default.temporaryDirectory, containing: name)
    }

    /// The names in `directory` that contain `name`, hidden ones included, read with `readdir` and off the main actor.
    ///
    /// The temporary directory is shared with every other tool on the machine and can hold tens of thousands of
    /// entries. `FileManager` took seconds to list that many, and it did so on the main actor, where every main-actor
    /// test in the run waited behind it. `readdir` takes a fraction of that, only the names that match become strings,
    /// and the listing runs beside the main actor rather than on it.
    @concurrent
    private nonisolated static func entries(in directory: URL, containing name: String) async throws -> [String] {
        guard let stream = opendir(directory.path(percentEncoded: false)) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { closedir(stream) }
        var matches: [String] = []
        while let entry = readdir(stream) {
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            let match = withUnsafePointer(to: entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { entryName in
                    strstr(entryName, name) != nil ? String(cString: entryName) : nil
                }
            }
            if let match { matches.append(match) }
        }
        return matches
    }
}
