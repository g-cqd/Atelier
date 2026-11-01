import AemiCore
import AtelierFileTree
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

// The badge states of a side's entries, read off the main actor; apart from the type's file, to keep it within the limits SwiftLint sets.
extension SideState {
    /// Re-reads git's status for this side's folder and swaps in the badge states it gives, without re-reading the
    /// files: staging or committing moves what the index holds, not what the files hold. A no-op for any other
    /// source; a later read or load supersedes it.
    package func refreshBadgeStates() {
        guard let source, case .directory = source else { return }
        let generation = beginBadgeStatesRead()
        let reader = reader
        badgeStatesTask = taskProvider.task {
            let states = await Self.readBadgeStates(of: source, reader: reader)
            guard !Task.isCancelled else { return }
            publish(states, generation: generation)
        }
    }

    /// Git's status for `source` as badge states, read and built off the main actor: nil when `source` is not a
    /// folder inside a repository, and when git fails, which leaves the side its look without git.
    @concurrent
    nonisolated static func readBadgeStates(of source: ComparisonSource, reader: any SourceReading) async
        -> BadgeChangeStates?
    {
        do {
            return try await reader.workingTreeStatus(of: source).map(BadgeChangeStates.init(status:))
        } catch is CancellationError {
            return nil
        } catch {
            PhaseTrace.log("git status failed for \(source.displayName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Supersedes every earlier read of git's status; returns the generation a new result must still hold to land.
    func beginBadgeStatesRead() -> Int {
        badgeStatesTask?.cancel()
        badgeStatesTask = nil
        badgeStatesGeneration += 1
        return badgeStatesGeneration
    }

    func publish(_ states: BadgeChangeStates?, generation: Int) {
        guard generation == badgeStatesGeneration else { return }
        gitBadgeStates = states
    }
}
