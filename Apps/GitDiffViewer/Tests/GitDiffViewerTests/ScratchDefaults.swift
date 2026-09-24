import Foundation
import Testing

/// A preferences suite for one test, which leaves nothing on disk once released. Every suite the tests write comes
/// from here.
///
/// A suite named like an app, `GitDiffViewerTests.x`, keeps its plist in `~/Library/Preferences`, and cfprefsd writes
/// every change to it after the first lazily, seconds later: once the suite is removed and its plist deleted, cfprefsd
/// still writes the plist back, empty, into the user's real preferences. So this suite is named by an absolute path
/// instead, into a directory of its own in the temporary directory: cfprefsd keeps the plist there, and the directory
/// goes with the suite.
///
/// Keep it for as long as anything writes to ``defaults``: as a stored property of the test's suite, or of the harness
/// that builds its models, so that it goes only after the test. A write that reaches cfprefsd once the directory is
/// gone makes it create the directory again.
final class ScratchDefaults {
    /// `GitDiffViewerTests.<tag>.<UUID>`: the name of the suite's directory and of its plist, and so of anything of
    /// either left behind.
    let name: String
    /// The suite, shared by every object the test hands it to.
    let defaults: UserDefaults
    /// Where cfprefsd keeps the suite's plist while the suite lives.
    let plist: URL
    /// The directory that holds ``plist`` and nothing else.
    private let directory: URL
    /// The suite's identifier: an absolute path, which cfprefsd takes for the plist's without its extension.
    private let suiteName: String

    /// Makes an empty suite; `tag` names the tests it serves.
    init(tag: String) {
        let name = "GitDiffViewerTests.\(tag).\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        let suiteName = directory.appending(path: name).path(percentEncoded: false)
        #expect(throws: Never.self) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults refuses only NSGlobalDomain and the main bundle's identifier")
        }
        self.name = name
        self.directory = directory
        self.suiteName = suiteName
        self.defaults = defaults
        plist = URL(filePath: suiteName + ".plist")
    }

    /// Removes the suite from cfprefsd and from the disk, in three steps, in this order:
    /// 1. Empty the domain, so that anything cfprefsd still writes of the suite, should the directory outlast this,
    ///    holds nothing the test wrote.
    /// 2. Synchronize, so that every write this process made to the suite, and the removal, has reached cfprefsd
    ///    before the directory goes: a write that reaches it after that makes it create the directory and the plist
    ///    again.
    /// 3. Remove the directory, not just the plist: cfprefsd writes a change seconds after it and puts a plist deleted
    ///    in between back, empty; with the directory gone, it has nowhere to write.
    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        CFPreferencesAppSynchronize(suiteName as CFString)
        try? FileManager.default.removeItem(at: directory)
    }
}
