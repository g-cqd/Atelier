package import AtelierDiagnostics

/// How many of a file's findings are each severity, for a badge that only ever shows warnings and errors.
package struct DiagnosticSeverityCounts: Equatable, Sendable {
    package let warnings: Int
    package let errors: Int

    package init(_ findings: [Finding]) {
        warnings = findings.count { $0.severity == .warning }
        errors = findings.count { $0.severity == .error }
    }

    package var isEmpty: Bool { warnings == 0 && errors == 0 }
}
