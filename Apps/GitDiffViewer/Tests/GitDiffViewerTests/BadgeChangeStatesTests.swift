import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``BadgeChangeStates``: git's status turned into each path's badge state, the folders above them aggregated, and
/// two sides merged for the unified explorer.
struct BadgeChangeStatesTests {
    /// Parses NUL-terminated porcelain v2 records, the format ``GitClient/status()`` asks git for.
    private static func status(_ records: [String]) -> [GitStatusEntry] {
        GitParsers.porcelainV2(Data((records.joined(separator: "\u{0}") + "\u{0}").utf8)).entries
    }

    private static func unstaged(_ path: String) -> String {
        "1 .M N... 100644 100644 100644 aaaa aaaa \(path)"
    }

    private static func staged(_ path: String) -> String {
        "1 M. N... 100644 100644 100644 aaaa bbbb \(path)"
    }

    @Test(arguments: [
        (["1 .M N... 100644 100644 100644 aaaa aaaa a.swift"], BadgeChangeState.unstaged),
        (["1 M. N... 100644 100644 100644 aaaa bbbb a.swift"], .staged),
        (["1 MM N... 100644 100644 100644 aaaa bbbb a.swift"], .unstaged),
        (["1 A. N... 000000 100644 100644 0000 bbbb a.swift"], .staged),
        (["1 AM N... 000000 100644 100644 0000 bbbb a.swift"], .unstaged),
        (["? a.swift"], .untracked),
        (["1 .D N... 100644 100644 000000 aaaa aaaa a.swift"], .unstaged),
        (["2 R. N... 100644 100644 100644 aaaa aaaa R100 a.swift", "old.swift"], .staged),
        (["2 RM N... 100644 100644 100644 aaaa bbbb R100 a.swift", "old.swift"], .unstaged),
        (["u UU N... 100644 100644 100644 100644 aaaa bbbb cccc a.swift"], .unstaged)
    ])
    func `git's status gives a file the state of its working tree side`(records: [String], state: BadgeChangeState) {
        #expect(BadgeChangeStates(status: Self.status(records)).state(of: "a.swift") == state)
    }

    @Test
    func `a committed file git's status leaves out is staged`() {
        let sut = BadgeChangeStates(status: Self.status([Self.unstaged("edited.swift"), "? new.swift"]))

        #expect(sut.state(of: "committed.swift") == .staged)
    }

    @Test
    func `a folder is unstaged when a file anywhere below it is`() {
        let sut = BadgeChangeStates(status: Self.status([Self.unstaged("Sources/App/Deep/a.swift")]))

        #expect(sut.state(of: "Sources") == .unstaged)
        #expect(sut.state(of: "Sources/App") == .unstaged)
        #expect(sut.state(of: "Sources/App/Deep") == .unstaged)
    }

    @Test
    func `a folder holding only new files is untracked until an unstaged file joins them, in any order`() {
        let entries = Self.status([
            "? fresh/a.swift", "? fresh/b.swift", "? mixed/new.swift", Self.unstaged("mixed/old.swift")
        ])

        for order in [entries, entries.reversed()] {
            let sut = BadgeChangeStates(status: order)
            #expect(sut.state(of: "fresh") == .untracked)
            #expect(sut.state(of: "mixed") == .unstaged)
        }
    }

    @Test
    func `a folder whose files are all staged or committed is staged, and so is one that merely shares a prefix`() {
        let sut = BadgeChangeStates(status: Self.status([Self.staged("done/a.swift"), Self.unstaged("work/b.swift")]))

        #expect(sut.state(of: "done") == .staged)
        #expect(sut.state(of: "work") == .unstaged)
        #expect(sut.state(of: "wor") == .staged)
        #expect(sut.state(of: "work-log") == .staged)
    }

    @Test
    func `an ignored path strokes nothing, not even the folder above it`() {
        let sut = BadgeChangeStates(status: Self.status(["! build/out.o", "! .build/"]))

        #expect(sut.state(of: "build/out.o") == .staged)
        #expect(sut.state(of: "build") == .staged)
        #expect(sut.state(of: ".build") == .staged)
    }

    @Test
    func `a side git knows nothing about gives every path one state`() {
        #expect(BadgeChangeStates.uniform(.unstaged).state(of: "any/path.swift") == .unstaged)
        #expect(BadgeChangeStates.uniform(.staged).state(of: "any") == .staged)
    }

    @Test
    func `merging follows a renamed file to its left-side path and aggregates the folders there`() {
        let right = BadgeChangeStates(status: Self.status([Self.unstaged("new/b.swift")]))

        let sut = BadgeChangeStates.merged(left: .uniform(.staged), right: right) {
            $0 == "new/b.swift" ? "old/b.swift" : $0
        }

        #expect(sut.state(of: "old/b.swift") == .unstaged)
        #expect(sut.state(of: "old") == .unstaged)
        #expect(sut.state(of: "new") == .staged)
    }

    @Test
    func `merging keeps the more pressing state, whether a side names the path or strokes everything`() {
        let left = BadgeChangeStates(status: Self.status(["? a.swift"]))
        let right = BadgeChangeStates(status: Self.status([Self.unstaged("a.swift")]))

        let named = BadgeChangeStates.merged(left: left, right: right) { $0 }
        let stroked = BadgeChangeStates.merged(left: .uniform(.unstaged), right: .uniform(.staged)) { $0 }

        #expect(named.state(of: "a.swift") == .unstaged)
        #expect(named.state(of: "b.swift") == .staged)
        #expect(stroked.state(of: "b.swift") == .unstaged)
    }
}
