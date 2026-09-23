package import AtelierDiagnostics

/// Groups a comparison's findings by file for the findings navigator: files sorted by path, each file's findings
/// by line then column.
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
