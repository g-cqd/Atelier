package import AtelierDiagnostics

/// Groups every finding of a comparison by file, for the findings navigator's toolbar popover: one entry per
/// file (sorted by path), its own findings sorted by line then column so the list reads top to bottom the way the
/// file itself does. Pure so the grouping and sort order are testable without a view or a model.
package enum FindingsNavigatorGrouping {
    package struct FileGroup: Equatable {
        package let path: String
        package let findings: [Finding]

        package init(path: String, findings: [Finding]) {
            self.path = path
            self.findings = findings
        }
    }

    package static func groups(_ findingsByFile: [String: [Finding]]) -> [FileGroup] {
        findingsByFile
            .filter { !$0.value.isEmpty }
            .map { path, findings in
                FileGroup(path: path, findings: findings.sorted(by: Self.isOrderedBefore))
            }
            .sorted { $0.path < $1.path }
    }

    private static func isOrderedBefore(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return (lhs.column ?? 0) < (rhs.column ?? 0)
    }
}
