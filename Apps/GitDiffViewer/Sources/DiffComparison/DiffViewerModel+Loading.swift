import DiffGit
import Foundation

/// The prologue of ``DiffViewerModel/compareGitChanges(in:leftRef:rightRef:)``: repository info and both file lists,
/// read off the main actor in one go.
extension DiffViewerModel {
    struct LoadedSides: Sendable {
        let info: RepositoryInfo
        let left: ComparisonSource
        let right: ComparisonSource
        /// Each side's files, with the commit a ref side named when they were listed.
        let leftListing: SideState.Listing?
        let rightListing: SideState.Listing?
        /// The working tree's badge states, read beside its entries; nil for a ref, or when git fails.
        let rightBadgeStates: BadgeChangeStates?
    }

    /// Reads the repository and both sides' listings, each indexed as it lands, all off the main actor, which only
    /// installs the result. `threadProbe` runs as the prologue starts and as each side's index is built.
    nonisolated static func loadSides(
        in url: URL, leftRef: String, rightRef: String?, reader: any SourceReading,
        threadProbe: (@Sendable () -> Void)? = nil
    ) async
        -> LoadedSides?
    {
        threadProbe?()
        guard let info = await reader.repositoryInfo(containing: url) else { return nil }
        let leftSource = ComparisonSource.gitRef(repository: info.root, ref: leftRef)
        let rightSource =
            rightRef.map { ComparisonSource.gitRef(repository: info.root, ref: $0) } ?? .directory(info.root)
        async let leftListing = SideState.listing(of: leftSource, reader: reader, threadProbe: threadProbe)
        async let rightListing = SideState.listing(of: rightSource, reader: reader, threadProbe: threadProbe)
        async let rightBadgeStates = SideState.readBadgeStates(of: rightSource, reader: reader)
        let loaded = LoadedSides(
            info: info, left: leftSource, right: rightSource, leftListing: try? await leftListing,
            rightListing: try? await rightListing, rightBadgeStates: await rightBadgeStates)
        PhaseTrace.log("prologue loaded")
        return loaded
    }
}
