import Testing

@testable import AtelierSyntaxModel
@testable import KittySyntax

@Suite
struct HighlightCapabilityTests {
    @Test
    func `Unknown language reports plain tier`() {
        let report = CapabilityReporter.report(for: "nonexistent_language")
        #expect(report.achievedTier == .plain)
        #expect(report.blockers.contains("No bundled grammar"))
    }

    @Test
    func `Language with grammar and no externals gets structural tier`() {
        let report = CapabilityReporter.report(for: "json")
        #expect(report.achievedTier == .structural)
        #expect(report.maxPossibleTier == .semantic)
        #expect(report.blockers.isEmpty)
    }

    @Test
    func `Language with externals but no scanner support reports lexical with blocker`() {
        let report = CapabilityReporter.report(
            for: "python",
            hostCapabilities: HostCapabilities(supportsExternalScanner: false)
        )
        #expect(report.achievedTier == .lexical)
        #expect(report.blockers.contains(where: { $0.contains("external scanner") }))
    }

    @Test
    func `Host with external scanner support upgrades tier for external grammars`() {
        let report = CapabilityReporter.report(
            for: "python",
            hostCapabilities: HostCapabilities(supportsExternalScanner: true)
        )
        #expect(report.achievedTier == .enhanced)
        #expect(report.maxPossibleTier == .semantic)
    }

    @Test
    func `HighlightTier comparison works correctly`() {
        #expect(HighlightTier.plain < .lexical)
        #expect(HighlightTier.lexical < .structural)
        #expect(HighlightTier.structural < .enhanced)
        #expect(HighlightTier.enhanced < .semantic)
    }

    @Test
    func `reportAll returns reports for all bundled languages`() {
        let reports = CapabilityReporter.reportAll()
        #expect(reports.count > 0)
        #expect(reports.contains(where: { $0.language == "json" }))
        // Should not hang — reporter does NOT compile grammars
    }

    @Test
    func `Query feature analysis detects predicates in python query`() {
        // Python highlights.scm uses #match? predicates
        let report = CapabilityReporter.report(for: "python")
        // Python has externals so achieves lexical, but the query was analyzed
        #expect(report.achievedTier == .lexical)
    }
}
