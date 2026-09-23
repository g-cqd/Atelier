import Foundation
import Testing

@testable import DiffComparison

/// ``GitMetadataLocation/resolve(root:read:)`` for plain repositories and linked worktrees, over an in-memory
/// `read`.
struct GitMetadataLocationTests {
    @Test
    func `a plain repository keeps gitDir and commonDir as the root's own .git`() {
        let location = GitMetadataLocation.resolve(root: "/repo") { _ in nil }
        #expect(location.gitDir == "/repo/.git")
        #expect(location.commonDir == "/repo/.git")
    }

    @Test
    func `.git content with no gitdir line is treated as a plain directory`() {
        let location = GitMetadataLocation.resolve(root: "/repo") { path in
            path == "/repo/.git" ? "not a worktree pointer\n" : nil
        }
        #expect(location.gitDir == "/repo/.git")
        #expect(location.commonDir == "/repo/.git")
    }

    @Test
    func `a linked worktree follows gitdir and commondir to their absolute targets`() {
        let location = GitMetadataLocation.resolve(root: "/worktree") { path in
            switch path {
                case "/worktree/.git": "gitdir: /main/.git/worktrees/feature\n"
                case "/main/.git/worktrees/feature/commondir": "/main/.git\n"
                default: nil
            }
        }
        #expect(location.gitDir == "/main/.git/worktrees/feature")
        #expect(location.commonDir == "/main/.git")
    }

    @Test
    func `a linked worktree's commondir resolves a relative path against its own git dir`() {
        let location = GitMetadataLocation.resolve(root: "/main/worktrees/feature") { path in
            switch path {
                case "/main/worktrees/feature/.git": "gitdir: /main/.git/worktrees/feature\n"
                case "/main/.git/worktrees/feature/commondir": "../..\n"
                default: nil
            }
        }
        #expect(location.gitDir == "/main/.git/worktrees/feature")
        #expect(location.commonDir == "/main/.git")
    }

    @Test
    func `a missing commondir falls back to the worktree's own git dir for both`() {
        let location = GitMetadataLocation.resolve(root: "/worktree") { path in
            path == "/worktree/.git" ? "gitdir: /main/.git/worktrees/feature\n" : nil
        }
        #expect(location.gitDir == "/main/.git/worktrees/feature")
        #expect(location.commonDir == "/main/.git/worktrees/feature")
    }

    @Test
    func `trailing slashes on root and pointer targets are normalized away`() {
        let location = GitMetadataLocation.resolve(root: "/repo/") { _ in nil }
        #expect(location.gitDir == "/repo/.git")
        #expect(location.commonDir == "/repo/.git")
    }

    @Test
    func `a gitdir line among blank or unrelated lines is still found`() {
        let location = GitMetadataLocation.resolve(root: "/worktree") { path in
            switch path {
                case "/worktree/.git": "\ngitdir: /main/.git/worktrees/feature\n\n"
                default: nil
            }
        }
        #expect(location.gitDir == "/main/.git/worktrees/feature")
    }
}
