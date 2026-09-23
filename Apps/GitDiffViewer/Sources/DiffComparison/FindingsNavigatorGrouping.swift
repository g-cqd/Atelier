package import AtelierDiagnostics

/// Groups a comparison's findings by file for the findings navigator: the right side's files, then the left side's,
/// each sorted by path, each file's findings by line then column.
package enum FindingsNavigatorGrouping {
    package struct FileGroup: Equatable {
        package let path: String
        package let findings: [Finding]
        /// The side the file's findings were found on, by the side's own path.
        package let side: DiagnosticsSide

        package init(path: String, findings: [Finding], side: DiagnosticsSide = .right) {
            self.path = path
            self.findings = findings
            self.side = side
        }
    }

    /// The right side's findings alone.
    package static func groups(_ findingsByFile: [String: [Finding]]) -> [FileGroup] {
        groups(right: findingsByFile, left: [:])
    }

    /// Each side's files in turn, the right side first, as the analyzed-sides setting left them (DIAG-08).
    package static func groups(right: [String: [Finding]], left: [String: [Finding]]) -> [FileGroup] {
        sideGroups(right, side: .right) + sideGroups(left, side: .left)
    }

    private static func sideGroups(_ findingsByFile: [String: [Finding]], side: DiagnosticsSide) -> [FileGroup] {
        findingsByFile
            .filter { !$0.value.isEmpty }
            .map { path, findings in
                FileGroup(path: path, findings: findings.sorted(by: Self.isOrderedBefore), side: side)
            }
            .sorted { $0.path < $1.path }
    }

    private static func isOrderedBefore(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return (lhs.column ?? 0) < (rhs.column ?? 0)
    }
}
