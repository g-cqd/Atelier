import DiffGit
import Foundation

/// The prologue of ``DiffViewerModel/compareGitChanges(in:leftRef:rightRef:)``: repository info and both file lists,
/// read off the main actor in one go.
extension DiffViewerModel {
    struct LoadedSides: Sendable {
        let info: RepositoryInfo
        let left: ComparisonSource
        let right: ComparisonSource
        let leftEntries: [SourceEntry]?
        let rightEntries: [SourceEntry]?
        /// The working tree's badge states, read beside its entries; nil for a ref, or when git fails.
        let rightBadgeStates: BadgeChangeStates?
    }

    static func loadSides(in url: URL, leftRef: String, rightRef: String?, reader: any SourceReading) async
        -> LoadedSides?
    {
        guard let info = await reader.repositoryInfo(containing: url) else { return nil }
        let leftSource = ComparisonSource.gitRef(repository: info.root, ref: leftRef)
        let rightSource =
            rightRef.map { ComparisonSource.gitRef(repository: info.root, ref: $0) } ?? .directory(info.root)
        async let leftEntries = reader.entries(of: leftSource)
        async let rightEntries = reader.entries(of: rightSource)
        async let rightBadgeStates = SideState.readBadgeStates(of: rightSource, reader: reader)
        let loaded = LoadedSides(
            info: info, left: leftSource, right: rightSource, leftEntries: try? await leftEntries,
            rightEntries: try? await rightEntries, rightBadgeStates: await rightBadgeStates)
        PhaseTrace.log("prologue loaded")
        return loaded
    }
}
