package import DiffGit
import Foundation

/// A selection under the grouping by commit shows the change its section stands for, not the comparison's (GIT-06
/// criterion 5, D39): a commit's own change from its first parent, Uncommitted Changes from `HEAD` to the working
/// tree. Earlier Changes needs no scope of its own: no listed commit touched its files, so for them the comparison's
/// own pairs are the range's base against the oldest listed commit's first parent.
extension DiffViewerModel {
    /// The change `key` shows when it names a commit or Uncommitted Changes, or a file under one; nil for any other
    /// selection, which shows the comparison's own diff.
    func selectionScope(for key: String) -> CommitScope? {
        guard let group = commitGroup(forSelection: key), case .applies(let range) = commitGroups.eligibility else {
            return nil
        }
        let path = ExplorerSection.path(inSelection: key)
        let rows = path.map { path in group.rows.filter { $0.path == path } } ?? group.rows
        switch group.kind {
            case .commit(let commit):
                return CommitScope(
                    key: key, commit: commit, repository: range.repository, rows: rows, isSingleFile: path != nil)
            case .uncommitted:
                guard let head = commitGroups.tipCommit, let workingTree = right.source else { return nil }
                let comparison = comparison
                return CommitScope(
                    key: key, head: head, repository: range.repository, workingTree: workingTree, rows: rows,
                    isSingleFile: path != nil, workingTreeEntry: { comparison.rightEntries[$0] })
            case .earlier:
                return nil
        }
    }

    /// Renders `scope`'s change: its one file on its own, or its files as cards, read from its own two sides.
    func render(_ scope: CommitScope, keepingPublished: Bool) {
        let target: RenderPipeline.Target
        if scope.isSingleFile, let file = scope.files.first {
            target = .file(file.pair)
        } else if !scope.isSingleFile, !scope.files.isEmpty {
            let pairs = scope.files.prefix(Self.combinedFileLimit).map(\.pair)
            // A fold of a file the list no longer holds would skew the fold count the toolbar reads.
            folding.keepOnly(Set(pairs.map(\.path)))
            target = .cards(Array(pairs))
        } else {
            // A file its section no longer lists, or a section with no files: nothing to show until the groups land.
            if !scope.isSingleFile { folding.keepOnly([]) }
            showsPreviousSelection = false
            pipeline.clear()
            timer.finish()
            return
        }
        PhaseTrace.log("render \(target.pairs.count) files of a commit group")
        pipeline.render(
            target, left: scope.left, right: scope.right, granularity: settings.granularity,
            heuristics: settings.diffHeuristics, keepingPublished: keepingPublished)
    }

    /// Sets ``commitScope`` only when it changes, so a render of the same selection invalidates nothing.
    func setCommitScope(_ scope: CommitScope?) {
        if commitScope != scope { commitScope = scope }
    }

    // MARK: What is shown, file by file

    /// The file a selection shows on its own, by the path its render names it: a plain file's path, or the path of a
    /// file's own change under a commit group; nil for a folder, a section, or nothing.
    package func filePath(forSelection key: String) -> String? {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return comparison.isFile(key) ? key : nil }
        guard let row = ExplorerSection.path(inSelection: key) else { return nil }
        if let scope = commitScope, scope.key == key { return scope.files.first?.pair.path }
        return row
    }

    /// The path a file on screen is named by: the change's own path under a commit group, else the comparison's.
    package func shownDisplayPath(for path: String) -> String {
        commitScope?.file(atPath: path) != nil ? path : displayPath(for: path)
    }

    /// How a card's header names a file on screen: under a commit group, the change's own paths, `new ← old` for a
    /// rename in that change (D14).
    package func cardLabel(for path: String) -> CardPathLabel {
        guard let file = commitScope?.file(atPath: path) else { return comparison.cardLabel(for: path) }
        return CardPathLabel(path: file.pair.path, previousPath: file.previousPath)
    }

    /// Where a file on screen stands in git, for its badge's fill: a commit's change is committed; the working tree's
    /// reads as its row does.
    package func shownBadgeState(ofPath path: String) -> BadgeChangeState {
        guard let scope = commitScope, let file = scope.file(atPath: path) else { return badgeState(ofPath: path) }
        if case .commit = scope.kind { return .staged }
        return badgeState(ofPath: file.rowPath)
    }

    /// The status a file on screen shows: its own change's under a commit group, else the comparison's.
    func shownStatus(ofPath path: String) -> PathStatus? {
        commitScope?.file(atPath: path)?.pathStatus ?? status(ofPath: path)
    }

    // MARK: Tabs

    /// Whether a tab's selection is a file: a plain file, or a file under a commit group.
    package func selectionIsFile(_ key: String) -> Bool {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return comparison.isFile(key) }
        return ExplorerSection.path(inSelection: key) != nil
    }

    /// The status a tab's badge letter shows: a file's own change under a commit or Uncommitted Changes, the
    /// comparison's elsewhere; nil for a section.
    package func selectionStatus(_ key: String) -> PathStatus? {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return status(ofPath: key) }
        guard let path = ExplorerSection.path(inSelection: key) else { return nil }
        guard let change = commitGroup(forSelection: key)?.rows.first(where: { $0.path == path })?.change else {
            return status(ofPath: path)
        }
        return CommitScope.pathStatus(of: change.status)
    }

    /// Where a tab's file stands in git: committed under a commit, as its row does under the other sections.
    package func selectionBadgeState(_ key: String) -> BadgeChangeState {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return badgeState(ofPath: key) }
        guard let path = ExplorerSection.path(inSelection: key) else { return badgeState(ofPath: key) }
        if case .commit? = commitGroup(forSelection: key)?.kind { return .staged }
        return badgeState(ofPath: path)
    }
}
