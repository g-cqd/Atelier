import DiffCore
package import DiffGit
import DiffRendering
import Foundation
import Observation

/// One file of the comparison: its left path and the entries on both sides, either of which may be missing.
package struct FilePair: Sendable, Equatable {
    package let path: String
    package let old: SourceEntry?
    package let new: SourceEntry?
}

/// Renamed files in both directions, kept together so the two maps cannot disagree.
package struct RenameMap: Sendable, Equatable {
    package private(set) var byLeft: [String: String] = [:]
    package private(set) var byRight: [String: String] = [:]

    package init(_ byLeft: [String: String] = [:]) {
        merge(byLeft)
    }

    /// Adds renames without overriding known ones.
    package mutating func merge(_ renames: [String: String]) {
        for (left, right) in renames where byLeft[left] == nil && byRight[right] == nil {
            byLeft[left] = right
            byRight[right] = left
        }
    }

    package var isEmpty: Bool { byLeft.isEmpty }
}

/// How the two sides relate, file by file: a pure value computed from both entry lists, so every status question
/// has one answer that cannot drift from another.
package struct Comparison: Sendable, Equatable {
    package private(set) var leftEntries: [String: SourceEntry]
    package private(set) var rightEntries: [String: SourceEntry]
    /// The lone file on each side when two single files are compared, which match whatever their names.
    package let singleFiles: (left: String, right: String)?
    package private(set) var renames: RenameMap
    package private(set) var statuses: [String: PathStatus] = [:]
    /// Files git ignores on either side. They are in the entries, so they can be shown, but not in the statuses,
    /// so they are neither changes nor counted as such.
    package private(set) var ignoredPaths: Set<String>

    package static let empty = Comparison(left: [], right: [], leftSource: nil, rightSource: nil)

    package init(
        left: [SourceEntry], right: [SourceEntry], leftSource: ComparisonSource?, rightSource: ComparisonSource?,
        leftIgnored: [SourceEntry] = [], rightIgnored: [SourceEntry] = [], gitRenames: [String: String] = [:]
    ) {
        leftEntries = Dictionary(
            (left + leftIgnored).map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        rightEntries = Dictionary(
            (right + rightIgnored).map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        ignoredPaths = Set(leftIgnored.map(\.relativePath)).union(rightIgnored.map(\.relativePath))
        if leftSource?.isSingleFile == true, rightSource?.isSingleFile == true,
            let leftPath = left.first?.relativePath, let rightPath = right.first?.relativePath
        {
            singleFiles = (leftPath, rightPath)
        } else {
            singleFiles = nil
        }
        renames = RenameMap(Self.exactRenames(left: left, right: right))
        renames.merge(gitRenames)
        statuses = computeStatuses(left: left, right: right)
    }

    package static func == (lhs: Comparison, rhs: Comparison) -> Bool {
        lhs.leftEntries == rhs.leftEntries && lhs.rightEntries == rhs.rightEntries && lhs.renames == rhs.renames
            && lhs.statuses == rhs.statuses && lhs.ignoredPaths == rhs.ignoredPaths
            && lhs.singleFiles?.left == rhs.singleFiles?.left && lhs.singleFiles?.right == rhs.singleFiles?.right
    }

    /// Replaces the ignored files of both sides, which arrive later than the listed ones and change no status.
    package mutating func setIgnored(left: [SourceEntry], right: [SourceEntry]) {
        for path in ignoredPaths {
            leftEntries[path] = nil
            rightEntries[path] = nil
        }
        for entry in left where leftEntries[entry.relativePath] == nil { leftEntries[entry.relativePath] = entry }
        for entry in right where rightEntries[entry.relativePath] == nil { rightEntries[entry.relativePath] = entry }
        ignoredPaths = Set(left.map(\.relativePath)).union(right.map(\.relativePath))
    }

    /// Adds renames git detected; statuses follow.
    package mutating func merge(gitRenames: [String: String]) {
        renames.merge(gitRenames)
        statuses = computeStatuses(
            left: leftEntries.values.filter { !ignoredPaths.contains($0.relativePath) },
            right: rightEntries.values.filter { !ignoredPaths.contains($0.relativePath) }
        )
    }

    /// Files present on one side only whose content exists unchanged on the other side under another path.
    package static func exactRenames(left: [SourceEntry], right: [SourceEntry]) -> [String: String] {
        let leftPaths = Set(left.map(\.relativePath))
        let rightPaths = Set(right.map(\.relativePath))
        var rightByBlob: [String: [String]] = [:]
        for entry in right where !leftPaths.contains(entry.relativePath) {
            guard let blob = entry.blobID else { continue }
            rightByBlob[blob, default: []].append(entry.relativePath)
        }
        var renames: [String: String] = [:]
        for entry in left where !rightPaths.contains(entry.relativePath) {
            guard let blob = entry.blobID, var candidates = rightByBlob[blob], !candidates.isEmpty else { continue }
            renames[entry.relativePath] = candidates.removeFirst()
            rightByBlob[blob] = candidates
        }
        return renames
    }

    private func computeStatuses(left: [SourceEntry], right: [SourceEntry]) -> [String: PathStatus] {
        var statuses: [String: PathStatus] = [:]
        statuses.reserveCapacity(left.count + right.count)
        for entry in left {
            let counterpart = rightEntries[counterpartPath(of: entry.relativePath, in: .left)]
            statuses[entry.relativePath] =
                if renames.byLeft[entry.relativePath] != nil {
                    .renamed
                } else {
                    counterpart.map { Self.isSame(entry, $0) ? .same : .different } ?? .onlyLeft
                }
        }
        for entry in right where statuses[counterpartPath(of: entry.relativePath, in: .right)] == nil {
            statuses[entry.relativePath] = .onlyRight
        }
        return statuses
    }

    /// Renamed files map to their other path; two single files compare with each other whatever their names;
    /// otherwise paths match one-to-one.
    package func counterpartPath(of path: String, in side: Side) -> String {
        switch side {
            case .left:
                if let renamed = renames.byLeft[path] { return renamed }
                if let singleFiles, path == singleFiles.left { return singleFiles.right }
            case .right:
                if let original = renames.byRight[path] { return original }
                if let singleFiles, path == singleFiles.right { return singleFiles.left }
        }
        return path
    }

    /// Whether `leftPath` names a file on either side, as opposed to a directory or nothing.
    package func isFile(_ leftPath: String) -> Bool {
        leftEntries[leftPath] != nil || rightEntries[counterpartPath(of: leftPath, in: .left)] != nil
    }

    /// Whether `leftPath` still names a file or a folder holding files.
    package func contains(_ leftPath: String) -> Bool {
        isFile(leftPath) || statuses.keys.contains { $0.hasPrefix(leftPath + "/") }
            || ignoredPaths.contains { $0.hasPrefix(leftPath + "/") }
    }

    /// Whether `leftPath` names a file git ignores.
    package func isIgnored(_ leftPath: String) -> Bool {
        ignoredPaths.contains(leftPath)
    }

    package var changedPathCount: Int {
        statuses.values.filter { $0 != .same }.count
    }

    /// Changed files under `folder` (or everywhere), in explorer order, capped so a whole repository stays responsive.
    /// A folder holding nothing but ignored files, such as a build directory, lists those instead.
    package func changedPaths(under folder: String?, limit: Int) -> [String] {
        let prefix = folder.map { $0 + "/" } ?? ""
        var paths = statuses.filter { $0.value != .same && $0.key.hasPrefix(prefix) }.map(\.key)
        if folder != nil, paths.isEmpty, !statuses.keys.contains(where: { $0.hasPrefix(prefix) }) {
            paths = ignoredPaths.filter { $0.hasPrefix(prefix) }
        }
        return Array(paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(limit))
    }

    package func pair(for leftPath: String) -> FilePair {
        FilePair(
            path: leftPath, old: leftEntries[leftPath], new: rightEntries[counterpartPath(of: leftPath, in: .left)])
    }

    /// The path a file is shown under: its destination when it was renamed.
    package func displayPath(for leftPath: String) -> String {
        renames.byLeft[leftPath] ?? leftPath
    }

    /// Whether a renamed file's content changed as well.
    package func isRenamedWithChanges(_ leftPath: String) -> Bool {
        guard let rightPath = renames.byLeft[leftPath], let old = leftEntries[leftPath],
            let new = rightEntries[rightPath]
        else { return false }
        return !Self.isSame(old, new)
    }

    package func summaryKind(for leftPath: String, directoryStatus: PathStatus?) -> FileChangeSummary.Kind {
        if directoryStatus == nil, ignoredPaths.contains(leftPath) {
            return leftEntries[leftPath] != nil ? .deleted : .added
        }
        return switch directoryStatus ?? statuses[leftPath] {
            case .onlyLeft: .deleted
            case .onlyRight: .added
            case .renamed: .renamed(to: renames.byLeft[leftPath] ?? leftPath)
            default: .modified
        }
    }

    package static func isSame(_ lhs: SourceEntry, _ rhs: SourceEntry) -> Bool {
        guard let left = lhs.blobID, let right = rhs.blobID else { return false }
        return left == right
    }
}
