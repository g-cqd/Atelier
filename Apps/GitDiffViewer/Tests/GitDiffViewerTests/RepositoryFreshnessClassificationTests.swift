import Testing

@testable import DiffComparison

/// ``RepositoryFreshness/classify(_:paths:)``: which callback each path the watcher reports feeds, in a plain
/// repository and in a linked worktree. Only `HEAD`, the index and the refs count inside the git dirs.
struct RepositoryFreshnessClassificationTests {
    private static let paths = RepositoryFreshness.WatchedPaths(
        root: "/repo", gitDir: "/repo/.git", commonDir: "/repo/.git")

    private func classify(_ path: String) -> RepositoryFreshness.Classification {
        RepositoryFreshness.classify(path, paths: Self.paths)
    }

    @Test
    func `classify tags .git-HEAD as head`() {
        #expect(classify("/repo/.git/HEAD") == .head)
    }

    @Test
    func `classify tags packed-refs as refs`() {
        #expect(classify("/repo/.git/packed-refs") == .refs)
    }

    @Test
    func `classify tags a loose ref under refs as refs`() {
        #expect(classify("/repo/.git/refs/heads/main") == .refs)
        #expect(classify("/repo/.git/refs/remotes/origin/main") == .refs)
    }

    @Test
    func `classify tags the index as index`() {
        #expect(classify("/repo/.git/index") == .index)
    }

    @Test
    func `classify tags every other .git path as ignored, so it costs nothing`() {
        for path in [
            "/repo/.git/index.lock", "/repo/.git/COMMIT_EDITMSG", "/repo/.git/objects/42/2c2b7a",
            "/repo/.git/logs/HEAD",
            "/repo/.git/FETCH_HEAD", "/repo/.git/HEAD.lock", "/repo/.git/packed-refs.lock"
        ] {
            #expect(classify(path) == .ignored, "\(path)")
        }
    }

    @Test
    func `a git dir reported itself re-reads HEAD, the refs and the index, and the root reloads the tree too`() {
        #expect(classify("/repo/.git") == .rescan(includesTree: false))
        #expect(classify("/repo") == .rescan(includesTree: true))
    }

    @Test
    func `classify names a tree path relative to the root, and drops a hidden one`() {
        #expect(classify("/repo/Sources/Foo.swift") == .tree("Sources/Foo.swift"))
        #expect(classify("/repo/.build/index-build/a.o") == .ignored)
    }

    @Test
    func `classify tags a path under a skipped directory as ignored`() {
        #expect(classify("/repo/node_modules/left-pad/index.js") == .ignored)
        #expect(classify("/repo/Sources/DerivedData/Foo.swift") == .ignored)
    }

    @Test
    func `classify tags a path outside the tree as ignored`() {
        #expect(classify("/somewhere/else.swift") == .ignored)
        #expect(classify("/repository/a.swift") == .ignored)
    }

    @Test
    func `in a linked worktree, its own HEAD and index and the shared refs count, the main worktree's do not`() {
        let paths = RepositoryFreshness.WatchedPaths(
            root: "/wt", gitDir: "/main/.git/worktrees/wt", commonDir: "/main/.git")

        #expect(RepositoryFreshness.classify("/main/.git/worktrees/wt/HEAD", paths: paths) == .head)
        #expect(RepositoryFreshness.classify("/main/.git/worktrees/wt/index", paths: paths) == .index)
        #expect(RepositoryFreshness.classify("/main/.git/refs/heads/feature", paths: paths) == .refs)
        #expect(RepositoryFreshness.classify("/main/.git/packed-refs", paths: paths) == .refs)
        #expect(RepositoryFreshness.classify("/main/.git/HEAD", paths: paths) == .ignored)
        #expect(RepositoryFreshness.classify("/main/.git/index", paths: paths) == .ignored)
        #expect(RepositoryFreshness.classify("/main/.git", paths: paths) == .rescan(includesTree: false))
        #expect(RepositoryFreshness.classify("/wt", paths: paths) == .rescan(includesTree: true))
        #expect(RepositoryFreshness.classify("/wt/a.swift", paths: paths) == .tree("a.swift"))
    }
}
