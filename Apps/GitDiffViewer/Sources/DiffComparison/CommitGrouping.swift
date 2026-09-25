import Darwin
package import DiffGit
package import Foundation

/// Whether the calling thread is the main thread, for asserting that work runs off it.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// The flat file list of one comparison split into a section per commit (GIT-06): a pure value built from the
/// comparison and the commits of its range, off the main actor, and replaced whole on every rebuild.
///
/// - A file sits under **each** commit that changed it (D29), and a section lists only the files the comparison's
///   net diff holds: a file changed and then changed back gets no row, and is counted instead.
/// - Renames are followed commit by commit, oldest first, so a file touched under an older name lands on the
///   comparison's own row, which keeps the new name (D14).
/// - Sections run newest first: Uncommitted Changes when the right side is the working tree, one per commit, then
///   Earlier Changes for the net files no listed commit touched, when there are any or when the listing stopped
///   short of the range's start.
package struct CommitGrouping: Sendable, Equatable {
    /// What a commit section shows of its commit: everything but its files.
    package struct Commit: Sendable, Hashable {
        package let id: String
        package let parentIDs: [String]
        package let authorName: String
        package let authorDate: Date
        package let subject: String

        package init(_ commit: GitCommitChanges) {
            id = commit.id
            parentIDs = commit.parentIDs
            authorName = commit.authorName
            authorDate = commit.authorDate
            subject = commit.subject
        }

        package var isMerge: Bool { parentIDs.count > 1 }
    }

    package enum Kind: Sendable, Hashable {
        /// The working tree's changes on top of the right side's `HEAD`.
        case uncommitted
        case commit(Commit)
        /// The net files no listed commit touched; `unlistedCommitCount` is how many commits of the range were not
        /// listed, nil when not known.
        case earlier(unlistedCommitCount: Int?)
    }

    /// One file under a section.
    package struct Row: Sendable, Hashable {
        /// The comparison's key for the file, as the flat list keys it: its left path, or its right path when only
        /// the right side has it.
        package let path: String
        /// The file's path in this section's change when it differs from the one the list shows, for the tooltip's
        /// "Named … in this commit"; nil otherwise.
        package let pathInChange: String?

        package init(path: String, pathInChange: String? = nil) {
            self.path = path
            self.pathInChange = pathInChange
        }
    }

    package struct Section: Sendable, Equatable, Identifiable {
        package static let noNetChangesNote = "No net changes: later commits changed these files back"
        package static let noFileChangesNote = "No file changes"
        package static let uncommittedNoNetChangesNote = "No net changes: these files match the left side again"

        package let kind: Kind
        /// The section's files in the flat list's order.
        package let rows: [Row]
        /// Files the section's change touched that the net diff does not hold, since a later change undid them.
        package let changedBackCount: Int

        package init(kind: Kind, rows: [Row], changedBackCount: Int = 0) {
            self.kind = kind
            self.rows = rows
            self.changedBackCount = changedBackCount
        }

        /// Stable across reloads, and the key the section's fold state is kept under.
        package var id: String {
            switch kind {
                case .uncommitted: "uncommitted"
                case .commit(let commit): "commit:\(commit.id)"
                case .earlier: "earlier"
            }
        }

        /// The inert line a section with no rows shows in their place; nil when it has rows.
        package var note: String? {
            guard rows.isEmpty else { return nil }
            switch kind {
                case .commit:
                    return changedBackCount > 0 ? Self.noNetChangesNote : Self.noFileChangesNote
                case .uncommitted:
                    return Self.uncommittedNoNetChangesNote
                case .earlier:
                    return nil
            }
        }
    }

    package let sections: [Section]
    /// True when the listing reached the range's start but its oldest commit's first parent is not the left side's
    /// commit: the left side sits inside a branch the right side merged later, so a first-parent listing's oldest
    /// merge also holds changes the left side already has, and the range should be listed again with every parent.
    package let leavesFirstParentChain: Bool

    package static let empty = CommitGrouping(sections: [], leavesFirstParentChain: false)

    package init(sections: [Section], leavesFirstParentChain: Bool) {
        self.sections = sections
        self.leavesFirstParentChain = leavesFirstParentChain
    }

    /// Groups the comparison's changed files by the commits that changed them.
    /// - Parameters:
    ///   - comparison: The net comparison of the range's two ends; only its changed files get rows.
    ///   - commits: The listed commits of the range, newest first, as `GitClient.commitChanges` returns them.
    ///   - uncommitted: The working tree's changes against `HEAD`, untracked files as additions, when the right
    ///     side is the working tree; nil otherwise.
    ///   - isComplete: Whether `commits` reach the range's start.
    ///   - unlistedCommitCount: How many commits of the range `commits` leaves out, when known.
    ///   - baseCommit: The left side's commit id, to tell whether a complete listing's oldest commit follows it
    ///     along first parents; nil skips the check.
    /// - Returns: The sections, newest first, and whether the listing left the first-parent chain.
    /// - Complexity: O(changes + rows log rows), dictionary lookups per change.
    package static func build(
        comparison: Comparison, commits: [GitCommitChanges], uncommitted: [GitFileChange]?, isComplete: Bool,
        unlistedCommitCount: Int? = nil, baseCommit: String? = nil
    ) -> CommitGrouping {
        var tracker = IdentityTracker()
        // Oldest first, so each rename moves a file's identity before a newer commit names it; the working tree last.
        let steps = commits.reversed().map(\.changes) + (uncommitted.map { [$0] } ?? [])
        let touched = steps.map { tracker.apply($0) }
        let rowsByIdentity = tracker.identities.map { rowKeys(of: $0, in: comparison) }

        var attributed: Set<String> = []
        func section(_ kind: Kind, _ touches: [Touch]) -> Section {
            var rows: [String: Row] = [:]
            var changedBack = 0
            for touch in touches {
                let keys = rowsByIdentity[touch.identity]
                if keys.isEmpty { changedBack += 1 }
                for key in keys where rows[key] == nil {
                    let shown = comparison.displayPath(for: key)
                    rows[key] = Row(path: key, pathInChange: touch.path == shown ? nil : touch.path)
                }
            }
            attributed.formUnion(rows.keys)
            return Section(kind: kind, rows: sorted(Array(rows.values)), changedBackCount: changedBack)
        }

        var sections: [Section] = []
        if let uncommitted, !uncommitted.isEmpty, let touches = touched.last {
            sections.append(section(.uncommitted, touches))
        }
        for (offset, commit) in commits.enumerated() {
            sections.append(section(.commit(Commit(commit)), touched[commits.count - 1 - offset]))
        }
        let unattributed = comparison.statuses.compactMap { path, status in
            status != .same && !attributed.contains(path) ? Row(path: path) : nil
        }
        if !unattributed.isEmpty || !isComplete {
            sections.append(
                Section(kind: .earlier(unlistedCommitCount: unlistedCommitCount), rows: sorted(unattributed)))
        }
        let leaves =
            isComplete && baseCommit != nil && commits.last.map { $0.parentIDs.first != baseCommit } == true
        return CommitGrouping(sections: sections, leavesFirstParentChain: leaves)
    }

    /// The same build as ``build(comparison:commits:uncommitted:isComplete:unlistedCommitCount:baseCommit:)``,
    /// always off the main actor.
    @concurrent
    package static func buildOffMain(
        comparison: Comparison, commits: [GitCommitChanges], uncommitted: [GitFileChange]?, isComplete: Bool,
        unlistedCommitCount: Int? = nil, baseCommit: String? = nil
    ) async -> CommitGrouping {
        assert(!isOnMainThread(), "buildOffMain must run off the main actor")
        return build(
            comparison: comparison, commits: commits, uncommitted: uncommitted, isComplete: isComplete,
            unlistedCommitCount: unlistedCommitCount, baseCommit: baseCommit)
    }

    /// The flat list's order: `localizedStandardCompare` on the row key, as `PathNode.flatList` sorts.
    private static func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The comparison's rows one file's identity lands on: the row of the name it had when first seen, and the row
    /// of the name it ends with, which are one row unless the net diff split a rename into a deletion and an
    /// addition. Only changed rows count; none at all means the file was changed back.
    private static func rowKeys(of identity: IdentityTracker.Identity, in comparison: Comparison) -> [String] {
        func isChanged(_ key: String) -> Bool {
            comparison.statuses[key].map { $0 != .same } ?? false
        }
        var keys: [String] = []
        if let origin = identity.origin, isChanged(origin) { keys.append(origin) }
        if let current = identity.current {
            let key = comparison.counterpartPath(of: current, in: .right)
            if isChanged(key), !keys.contains(key) { keys.append(key) }
        }
        return keys
    }
}

/// One file a step changed: which identity, under which path in that step.
private struct Touch {
    let identity: Int
    let path: String
}

/// Follows files through a sequence of changes, oldest first, giving each file one identity across its renames.
private struct IdentityTracker {
    struct Identity {
        /// The path the file had before the first change seen; nil for a file one of the changes added.
        var origin: String?
        /// The path the file has after the last change seen; nil once deleted.
        var current: String?
    }

    private(set) var identities: [Identity] = []
    private var byPath: [String: Int] = [:]

    /// Applies one commit's changes, all read against the paths before it, so a commit that swaps two names moves
    /// each file once. Returns the identities it touched, each once.
    mutating func apply(_ changes: [GitFileChange]) -> [Touch] {
        var touches: [Touch] = []
        var moves: [(identity: Int, from: String)] = []
        var destinations: [Int: String?] = [:]
        for change in changes {
            let before = change.status == .renamed ? change.oldPath ?? change.path : change.path
            let identity: Int
            if let known = byPath[before] {
                identity = known
            } else {
                identity = identities.count
                identities.append(Identity(origin: change.status == .added ? nil : before, current: before))
            }
            touches.append(Touch(identity: identity, path: change.path))
            switch change.status {
                case .deleted:
                    moves.append((identity, before))
                    destinations[identity] = .some(nil)
                case .renamed:
                    moves.append((identity, before))
                    destinations[identity] = change.path
                case .added, .modified:
                    break
            }
        }
        for move in moves where byPath[move.from] == move.identity {
            byPath[move.from] = nil
        }
        for touch in touches {
            let destination = destinations[touch.identity] ?? touch.path
            identities[touch.identity].current = destination
            if let destination { byPath[destination] = touch.identity }
        }
        var seen: Set<Int> = []
        return touches.filter { seen.insert($0.identity).inserted }
    }
}
