import AemiCore
package import DiffGit
package import Foundation

/// What the merged sidebar shows of the grouping by commit (GIT-06): whether it applies, and the groups once loaded.
package struct CommitGroupsState: Equatable, Sendable {
    /// Whether grouping applies and why not; nil while the setting is off.
    package var eligibility: CommitGroupingEligibility?
    /// The groups last built; kept while newer ones load, so the sidebar never falls back to the plain list meanwhile.
    package var grouping: CommitGrouping?
    /// ``grouping``'s sections as the explorer lists them, built off the main actor with it.
    package var sections: [ExplorerSection] = []
    /// Pages are loading or the groups are being rebuilt; what is shown is the previous state until they land.
    package var isUpdating = false
    /// The range was listed with every parent, since the left side sits inside a branch the right side merged.
    package var includesMergedBranches = false
    /// The commit the range's tip resolved to when ``grouping`` was built: `HEAD`'s when the right side is the working
    /// tree, which Uncommitted Changes shows its files against (D39).
    package var tipCommit: String?

    package static let off = CommitGroupsState()

    /// Why grouping does not apply to this window, for the View options menu's subtitle and the sidebar's line.
    package var unavailableReason: String? { eligibility?.ineligibility?.message }
}

/// The commits of a range as listed so far, kept between loads so a reload of the same range lists nothing again,
/// and a right side moved forward lists only its new commits.
struct CommitListing: Sendable, Equatable {
    let repository: URL
    let baseID: String
    let tipID: String
    /// Newest first.
    var commits: [GitCommitChanges] = []
    var isComplete = false
    /// The tip of the next first-parent page; nil once the range ended, and for a listing of every parent.
    var nextTip: String?
    var firstParent = true
    /// Commits of the range past the cap; nil until counted, and while the listing is complete.
    var unlistedCount: Int?

    init(repository: URL, baseID: String, tipID: String) {
        self.repository = repository
        self.baseID = baseID
        self.tipID = tipID
        nextTip = tipID
    }

    /// No more pages to load: the range ended, the cap is reached, or the listing took every parent in one run.
    var isFinished: Bool { isComplete || commits.count >= DiffViewerModel.commitGroupCap || !firstParent }

    mutating func append(_ page: GitCommitPage) {
        commits += page.commits
        isComplete = page.isComplete
        nextTip = page.continuation
    }

    /// Whether a complete first-parent listing started from the left side's commit; when it did not, the left side
    /// sits inside a merged branch and the oldest merge would also hold changes the left side already has.
    var leavesFirstParentChain: Bool {
        guard firstParent, isComplete, let oldest = commits.last else { return false }
        return oldest.parentIDs.first != baseID
    }
}

/// Loading the grouping by commit: the ancestry checks, then pages of commits up to the cap, each rebuilt into
/// groups off the main actor as it lands (GIT-06, design note steps 1 to 5).
extension DiffViewerModel {
    /// Commits a page lists; the first lands quickly whatever the range's length.
    package nonisolated static let commitGroupPageSize = 200
    /// Commits listed at most; the rest go into Earlier Changes.
    package nonisolated static let commitGroupCap = 1_000

    /// Re-evaluates the grouping after a change. `force` starts over from the ancestry checks, as a new comparison, a
    /// reload or new renames need; otherwise nothing runs when placement, style and sides still ask what they asked,
    /// so an unrelated setting change costs no git run.
    func refreshCommitGroups(force: Bool) {
        guard settings.groupsByCommit else {
            cancelCommitGroups()
            commitGroupsRequest = nil
            commitGroups = .off
            dropVanishedCommitGroupTabs()
            return
        }
        // The comparison is the one on screen until both sides land; the groups wait for it too.
        guard !left.isLoading, !right.isLoading, failedLoads.isEmpty else { return }
        let verdict = CommitGroupingEligibility.evaluate(
            placement: settings.explorerPlacement, style: settings.treeStyle, left: left.source, right: right.source)
        guard force || verdict != commitGroupsRequest else { return }
        commitGroupsRequest = verdict
        cancelCommitGroups()
        guard case .needsAncestry(let range) = verdict else {
            commitGroups = CommitGroupsState(eligibility: verdict)
            dropVanishedCommitGroupTabs()
            return
        }
        guard let history else {
            commitGroups = CommitGroupsState(eligibility: .doesNotApply(.historyUnreadable("git is not available")))
            dropVanishedCommitGroupTabs()
            return
        }
        commitGroups.eligibility = verdict
        commitGroups.isUpdating = true
        let generation = commitGroupsGeneration
        let comparison = comparison
        commitGroupsTask = taskProvider.task { [weak self] in
            await self?.loadCommitGroups(range, comparison: comparison, history: history, generation: generation)
        }
    }

    /// Takes the way out a "doesn't apply" state offers (GIT-06, D30, D32): the merged sidebar, the flat list, the sides
    /// swapped, or the left side moved to the merge base of a diverged comparison, which is GitHub's view of it.
    package func perform(_ action: CommitGroupingAction) {
        switch action {
            case .useMergedSidebar: settings.explorerPlacement = .unifiedSidebar
            case .useFlatList: settings.treeStyle = .flat
            case .swapSides: swapSides()
            case .compareFromMergeBase(let commit):
                guard case .gitRef(let repository, _)? = left.source else { return }
                left.load(.gitRef(repository: repository, ref: commit), repository: left.repository)
        }
    }

    /// Stops any load in flight, which terminates its git run, and makes a load that already returned stale.
    func cancelCommitGroups() {
        commitGroupsTask?.cancel()
        commitGroupsTask = nil
        commitGroupsGeneration += 1
    }

    private func loadCommitGroups(
        _ range: CommitGroupingRange, comparison: Comparison, history: CommitHistory, generation: Int
    ) async {
        let repository = range.repository
        do {
            async let baseID = history.resolve(range.base, in: repository)
            async let tipID = history.resolve(range.tip, in: repository)
            let base = try await baseID
            let tip = try await tipID
            let ancestry = try await history.ancestry(of: base, and: tip, in: repository)
            guard generation == commitGroupsGeneration else { return }
            let eligibility = CommitGroupingEligibility.evaluate(
                placement: settings.explorerPlacement, style: settings.treeStyle, left: left.source,
                right: right.source, ancestry: ancestry)
            guard case .applies = eligibility else {
                commitGroups = CommitGroupsState(eligibility: eligibility)
                dropVanishedCommitGroupTabs()
                return
            }
            commitGroups.eligibility = eligibility
            let uncommitted = range.includesWorkingTree ? try await history.uncommittedChanges(in: repository) : nil
            var listing = try await Self.startingListing(
                repository: repository, baseID: base, tipID: tip, cached: commitListing, history: history)
            guard generation == commitGroupsGeneration else { return }
            if !listing.commits.isEmpty, !listing.isFinished {
                await publish(listing, comparison: comparison, uncommitted: uncommitted, generation: generation)
            }
            while !listing.isFinished, let next = listing.nextTip {
                let page = try await history.commitChanges(
                    from: base, to: next, firstParent: true,
                    limit: min(Self.commitGroupPageSize, Self.commitGroupCap - listing.commits.count), in: repository)
                guard generation == commitGroupsGeneration else { return }
                listing.append(page)
                guard !listing.isFinished else { break }
                await publish(listing, comparison: comparison, uncommitted: uncommitted, generation: generation)
            }
            if listing.leavesFirstParentChain {
                listing = try await Self.everyParent(of: listing, history: history)
            } else if !listing.isComplete, listing.unlistedCount == nil {
                let total = try await history.commitCount(from: base, to: tip, in: repository)
                listing.unlistedCount = max(0, total - listing.commits.count)
            }
            guard generation == commitGroupsGeneration else { return }
            commitListing = listing
            await publish(
                listing, comparison: comparison, uncommitted: uncommitted, generation: generation, final: true)
        } catch is CancellationError {
            return
        } catch {
            guard generation == commitGroupsGeneration else { return }
            commitGroups = CommitGroupsState(eligibility: .doesNotApply(.historyUnreadable(error.localizedDescription)))
            dropVanishedCommitGroupTabs()
        }
    }

    /// Rebuilds the groups from `listing` off the main actor and shows them, unless a newer load started meanwhile.
    private func publish(
        _ listing: CommitListing, comparison: Comparison, uncommitted: [GitFileChange]?, generation: Int,
        final: Bool = false
    ) async {
        let built = await Self.buildGroups(listing, comparison: comparison, uncommitted: uncommitted)
        guard generation == commitGroupsGeneration, case .applies = commitGroups.eligibility else { return }
        commitGroups.grouping = built.grouping
        commitGroups.sections = built.sections
        commitGroups.includesMergedBranches = !listing.firstParent
        commitGroups.tipCommit = listing.tipID
        commitGroups.isUpdating = !final
        if final {
            dropVanishedCommitGroupTabs()
            // A selected group's files, or a file under one, may have changed with the groups: show them as they now
            // stand.
            if let selectedPath, ExplorerSection.groupID(inSelection: selectedPath) != nil { render() }
        }
    }

    @concurrent
    private static func buildGroups(
        _ listing: CommitListing, comparison: Comparison, uncommitted: [GitFileChange]?
    ) async -> (grouping: CommitGrouping, sections: [ExplorerSection]) {
        let grouping = CommitGrouping.build(
            comparison: comparison, commits: listing.commits, uncommitted: uncommitted,
            isComplete: listing.isComplete, unlistedCommitCount: listing.unlistedCount,
            baseCommit: listing.firstParent ? listing.baseID : nil)
        return (grouping, grouping.sections.map(ExplorerSection.init(group:)))
    }

    /// Where a load starts: the cached listing when it covers the same range, the cached one with the right side's
    /// new first-parent commits put on top when the right side only moved forward, or nothing.
    private nonisolated static func startingListing(
        repository: URL, baseID: String, tipID: String, cached: CommitListing?, history: CommitHistory
    ) async throws -> CommitListing {
        let fresh = CommitListing(repository: repository, baseID: baseID, tipID: tipID)
        guard let cached, cached.repository == repository, cached.baseID == baseID, cached.isFinished else {
            return fresh
        }
        if cached.tipID == tipID { return cached }
        guard cached.firstParent,
            try await history.ancestry(of: cached.tipID, and: tipID, in: repository) == .leftIsAncestor
        else { return fresh }
        let page = try await history.commitChanges(
            from: cached.tipID, to: tipID, firstParent: true, limit: commitGroupCap, in: repository)
        // Only commits stacked on the old tip along first parents can go on top of its listing.
        guard page.isComplete, page.commits.last.map({ $0.parentIDs.first == cached.tipID }) ?? true else {
            return fresh
        }
        var moved = fresh
        let commits = page.commits + cached.commits
        moved.commits = Array(commits.prefix(commitGroupCap))
        if commits.count > commitGroupCap {
            moved.isComplete = false
            moved.nextTip = moved.commits.last?.parentIDs.first
        } else {
            moved.isComplete = cached.isComplete
            moved.nextTip = cached.nextTip
            moved.unlistedCount = cached.unlistedCount.map { max(0, $0 - page.commits.count) }
        }
        return moved
    }

    /// The range listed again with every parent, up to the cap, for a left side inside a merged branch.
    private nonisolated static func everyParent(of listing: CommitListing, history: CommitHistory) async throws
        -> CommitListing
    {
        let page = try await history.commitChanges(
            from: listing.baseID, to: listing.tipID, firstParent: false, limit: commitGroupCap,
            in: listing.repository)
        var every = CommitListing(repository: listing.repository, baseID: listing.baseID, tipID: listing.tipID)
        every.commits = page.commits
        every.isComplete = page.isComplete
        every.nextTip = nil
        every.firstParent = false
        return every
    }
}
