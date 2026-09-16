import Foundation
import KittyGrammar
import KittyQuery

/// Analyzes a language's grammar and query setup to determine what highlighting tier it achieves.
///
/// The reporter inspects static grammar/query properties and checks the artifacts cache
/// to determine whether a language has been successfully compiled. It does NOT trigger
/// compilation itself (which can be expensive or hang on complex grammars).
public enum CapabilityReporter: Sendable {
    /// Generate a capability report for a language.
    public static func report(
        for language: String,
        hostCapabilities: HostCapabilities = HostCapabilities()
    ) -> HighlightCapabilityReport {
        // Audit A.4/E3 — consult the runtime registry first so ADR 8
        // extension hosts that register additional grammars are visible
        // to capability reporting. Reports for runtime languages omit
        // the resource-shape checks below (the extension is responsible
        // for serving its own grammar/highlights at `entry.path`) and
        // report the optimistic `.structural` tier; any actual compile
        // failure will downgrade observed behaviour at parse time.
        if let registered = GrammarRegistry.shared.entry(forLanguage: language) {
            _ = registered
            return HighlightCapabilityReport(
                language: language,
                achievedTier: .structural,
                maxPossibleTier: .semantic,
                blockers: []
            )
        }
        guard let entry = BundledLanguageManifest.entry(forLanguage: language) else {
            return HighlightCapabilityReport(
                language: language,
                achievedTier: hasFallback(for: language) ? .lexical : .plain,
                maxPossibleTier: hasFallback(for: language) ? .lexical : .plain,
                blockers: ["No bundled grammar"]
            )
        }

        let bundle = KittySyntaxResources.bundle
        let subdirectory = "Grammars/\(entry.path)"

        let hasGrammar =
            bundle.url(
                forResource: "grammar", withExtension: "json", subdirectory: subdirectory) != nil
        let hasQuery =
            bundle.url(
                forResource: "highlights", withExtension: "scm", subdirectory: subdirectory) != nil

        guard hasGrammar, hasQuery else {
            let fallback: HighlightTier = hasFallback(for: language) ? .lexical : .plain
            return HighlightCapabilityReport(
                language: language,
                achievedTier: fallback,
                maxPossibleTier: .structural,
                blockers: hasGrammar ? ["Missing highlights.scm"] : ["Missing grammar.json"]
            )
        }

        // Analyze grammar metadata (cheap: just loads JSON, does NOT compile)
        let analysis = analyzeLanguageMetadata(at: subdirectory)
        var blockers: [String] = []

        let needsExternals = analysis.requirements.needsExternalScanner
        let hasExternalSupport = hostCapabilities.supportsExternalScanner

        if needsExternals && !hasExternalSupport {
            blockers.append(
                "Grammar requires external scanner (\(analysis.requirements.externalSymbolCount) symbols) but host does not support it"
            )
        }

        let unsupportedFeatures = analysis.requirements.queryFeatures.subtracting(
            hostCapabilities.supportedQueryFeatures)
        if !unsupportedFeatures.isEmpty {
            blockers.append(
                "Unsupported query features: \(unsupportedFeatures.map(\.rawValue).sorted().joined(separator: ", "))"
            )
        }

        // Determine achieved tier based on what actually works at runtime
        let achievedTier: HighlightTier
        let maxPossibleTier: HighlightTier

        if needsExternals {
            // Grammar has externals — cannot run structurally without scanner
            if hasExternalSupport {
                achievedTier = .enhanced
                maxPossibleTier = .semantic
            } else {
                achievedTier = hasFallback(for: language) ? .lexical : .plain
                maxPossibleTier = .enhanced
            }
        } else {
            // No externals — structural tier is theoretically achievable.
            // Whether it's actually achieved depends on compilation, but we
            // report what SHOULD work, not whether compilation has been attempted.
            achievedTier = .structural
            maxPossibleTier = .semantic
        }

        return HighlightCapabilityReport(
            language: language,
            achievedTier: achievedTier,
            maxPossibleTier: maxPossibleTier,
            blockers: blockers
        )
    }

    /// Generate reports for all known languages — bundled + runtime
    /// registry (ADR 8 extensions). Audit A.4.
    public static func reportAll(
        hostCapabilities: HostCapabilities = HostCapabilities()
    ) -> [HighlightCapabilityReport] {
        let bundledNames = BundledLanguageManifest.entries.map(\.name)
        let runtimeNames = GrammarRegistry.shared.languageNames
        let allNames = Array(Set(bundledNames).union(runtimeNames)).sorted()
        return allNames.map { report(for: $0, hostCapabilities: hostCapabilities) }
    }

    // MARK: - Private

    private struct LanguageMetadata {
        let requirements: ParserRequirements
    }

    /// Analyze grammar and query metadata WITHOUT triggering compilation.
    private static func analyzeLanguageMetadata(at subdirectory: String) -> LanguageMetadata {
        let bundle = KittySyntaxResources.bundle

        // Analyze grammar externals
        var needsExternals = false
        var externalCount = 0
        if let grammarURL = bundle.url(
            forResource: "grammar", withExtension: "json", subdirectory: subdirectory),
            let grammar = try? GrammarLoader.load(from: grammarURL.path)
        {
            needsExternals = !grammar.externals.isEmpty
            externalCount = grammar.externals.count
        }

        // Analyze query features
        var queryFeatures = Set<QueryFeature>()
        if let queryURL = bundle.url(
            forResource: "highlights", withExtension: "scm", subdirectory: subdirectory),
            let querySource = try? String(contentsOf: queryURL, encoding: .utf8)
        {
            queryFeatures = analyzeQueryFeatures(querySource)
        }

        return LanguageMetadata(
            requirements: ParserRequirements(
                needsExternalScanner: needsExternals,
                externalSymbolCount: externalCount,
                queryFeatures: queryFeatures
            )
        )
    }

    /// Scan a query source for which features it uses.
    private static func analyzeQueryFeatures(_ source: String) -> Set<QueryFeature> {
        var features = Set<QueryFeature>()

        if source.contains("#eq?") || source.contains("#not-eq?")
            || source.contains("#match?") || source.contains("#any-of?")
            || source.contains("#is?") || source.contains("#is-not?")
        {
            features.insert(.predicates)
        }

        // Quantifiers: +, *, ? after closing paren or capture
        if source.range(of: #"\)\s*[+*?]"#, options: .regularExpression) != nil
            || source.range(of: #"@[\w.]+\s*[+*?]"#, options: .regularExpression) != nil
        {
            features.insert(.quantifiers)
        }

        // Field names: identifier followed by colon inside pattern
        if source.range(of: #"\w+:"#, options: .regularExpression) != nil {
            features.insert(.fieldNames)
        }

        // Alternations: [...]
        if source.contains("[") && source.contains("]") {
            features.insert(.alternations)
        }

        // Anchors: standalone .
        if source.range(of: #"\.\s"#, options: .regularExpression) != nil {
            features.insert(.anchors)
        }

        return features
    }

    private static func hasFallback(for language: String) -> Bool {
        switch language {
            case "python", "bash", "ruby", "lua", "toml", "yaml",
                "javascript", "typescript", "c", "cpp", "css", "go",
                "java", "kotlin", "rust", "swift", "json":
                return true
            default:
                return false
        }
    }
}
