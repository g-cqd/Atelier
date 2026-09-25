import AtelierGrammarCorpus
import AtelierQuery
import AtelierSyntaxModel
import Foundation
import Testing

@testable import KittySyntax

/// Every capture of every bundled highlight query gets from its index the role its name maps to, so resolving the
/// roles once per query changes no colour.
struct BundledCaptureRolesTests {
    @Test(arguments: BundledLanguageManifest.entries.map(\.path))
    func `roles by capture index equal the roles mapped from every capture name of a bundled query`(
        language: String
    ) throws {
        let resourcePath = try #require(KittySyntaxResources.resourcePath)
        let source = try String(contentsOfFile: "\(resourcePath)/Grammars/\(language)/highlights.scm", encoding: .utf8)
        // The queries `QueryParser` does not read yet (BundledHighlightQueryTests) have no captures to resolve.
        guard let query = try? QueryParser.parse(source) else { return }
        let roles = CaptureRoles(captureNames: query.captureNames)

        var captures: [QueryPattern.Capture] = []
        for pattern in query.patterns { Self.collectCaptures(pattern, into: &captures) }
        #expect(!captures.isEmpty)
        #expect(Set(captures.map(\.name)) == Set(query.captureNames))
        for capture in captures {
            #expect(query.captureNames[capture.index] == capture.name)
            let expected = CaptureRoleMapper.colorsText(capture.name) ? CaptureRoleMapper.map(capture.name) : nil
            #expect(roles[capture.index]?.role == expected?.role, "\(capture.name)")
            #expect(roles[capture.index]?.modifiers == expected?.modifiers, "\(capture.name)")
            #expect((roles[capture.index] == nil) == (expected == nil), "\(capture.name)")
        }
    }

    private static func collectCaptures(_ pattern: QueryPattern, into captures: inout [QueryPattern.Capture]) {
        switch pattern {
            case .nodeMatch(_, let children, let capture):
                for child in children { collectCaptures(child, into: &captures) }
                if let capture { captures.append(capture) }
            case .literal(_, let capture), .wildcard(let capture):
                if let capture { captures.append(capture) }
            case .fieldMatch(_, let inner), .quantified(let inner, _):
                collectCaptures(inner, into: &captures)
            case .alternation(let patterns), .sequence(let patterns):
                for inner in patterns { collectCaptures(inner, into: &captures) }
            case .negatedField, .predicate, .anchor:
                break
        }
    }
}
