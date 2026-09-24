import AtelierScanners
import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import KittySyntax

/// Opt-in measurements of one bundled grammar per process; set `GDV_BENCH` and `ATELIER_GRAMMAR_MEASURE_NAME`.
///
/// - The compile: its time, and how far it raised the process's peak footprint.
/// - With `ATELIER_CORPUS_DIR`, the grammar's pinned upstream corpus, `<dir>/<name>/*.txt` (the grammar's
///   `SOURCE.json` names the repository and commit): each case parsed with the grammar's scanner and compared with
///   the tree tree-sitter gives, the first divergence of each mismatch, and the ERROR nodes and bytes of the parses,
///   with the scanner and without it.
/// - With `ATELIER_LARGE_SAMPLE_DIR`, each file of `<dir>/<name>/`: its parse time, ERROR nodes and bytes, and
///   whether the highlighter keeps the grammar for it after its quality gate.
@Suite
struct BundledGrammarMeasurements {
    private static let environment = ProcessInfo.processInfo.environment

    @Test(
        .enabled(
            if: environment["GDV_BENCH"] != nil && environment["ATELIER_GRAMMAR_MEASURE_NAME"] != nil))
    func `measures a bundled grammar against its upstream corpus and large samples`() async throws {
        let name = try #require(Self.environment["ATELIER_GRAMMAR_MEASURE_NAME"])
        let resources = try #require(KittySyntaxResources.bundle.resourcePath)
        let grammar = try GrammarLoader.load(from: "\(resources)/Grammars/\(name)/grammar.json")
        let clock = ContinuousClock()
        let footprintBefore = Self.footprint()
        let start = clock.now
        let compiled = try ParseTableCompiler.compile(grammar)
        let compileTime = start.duration(to: clock.now)
        let peakRise = Self.footprint().peak - footprintBefore.peak
        print(
            "MEASURE \(name) compile: \(compileTime), peak footprint +\(peakRise / 1_048_576) MiB, "
                + "\(compiled.parseTable.stateCount) states, \(compiled.lexTable.automaton.count) lexer states")

        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let scannerType = BundledScanners.byGrammarName[grammar.name]
        let hidden = Set(grammar.supertypes)
        let extras = Set(
            grammar.extras.compactMap { rule -> String? in if case .symbol(let name) = rule { name } else { nil } })
        if let corpus = Self.environment["ATELIER_CORPUS_DIR"] {
            try measureCorpus(
                name: name, directory: URL(filePath: corpus).appending(path: name), parser: parser,
                scannerType: scannerType, hidden: hidden, extras: extras)
        }
        if let samples = Self.environment["ATELIER_LARGE_SAMPLE_DIR"] {
            try await measureSamples(
                name: name, directory: URL(filePath: samples).appending(path: name), parser: parser,
                scannerType: scannerType)
        }
    }

    // MARK: - Corpus

    private func measureCorpus(
        name: String, directory: URL, parser: GrammarParser, scannerType: (any GrammarExternalScanner.Type)?,
        hidden: Set<String>, extras: Set<String>
    ) throws {
        var withScanner = CorpusTally()
        var withoutScanner = CorpusTally()
        for file in try Self.files(in: directory) where file.pathExtension == "txt" {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for corpusCase in UpstreamCorpusCase.cases(
                in: contents, file: file.lastPathComponent, language: name)
            {
                guard !corpusCase.isSkipped, let expected = corpusCase.expected?.removing(extras) else {
                    withScanner.skipped += 1
                    continue
                }
                if let divergence = withScanner.add(
                    corpusCase, expected: expected,
                    tree: try? parser.parse(corpusCase.input, externalScanner: scannerType?.init()),
                    hidden: hidden, extras: extras)
                {
                    print("DIVERGE \(name) \(corpusCase.file) “\(corpusCase.name)”\(divergence)")
                }
                if scannerType != nil {
                    _ = withoutScanner.add(
                        corpusCase, expected: expected, tree: try? parser.parse(corpusCase.input), hidden: hidden,
                        extras: extras)
                }
            }
        }
        print("MEASURE \(name) corpus with scanner: \(withScanner.summary)")
        if scannerType != nil {
            print("MEASURE \(name) corpus without scanner: \(withoutScanner.summary)")
        }
    }

    /// Counts of a corpus's cases and of the ERROR nodes and bytes of their parses.
    private struct CorpusTally {
        var matched = 0
        var diverged = 0
        var failed = 0
        var recoveryMatched = 0
        var recoveryCases = 0
        var skipped = 0
        var errors = ErrorCounts()

        /// Adds a case's parse, `tree`, nil when the parse threw; returns how it departs from the expected tree.
        mutating func add(
            _ corpusCase: UpstreamCorpusCase, expected: CorpusTreeNode, tree: SyntaxTree?, hidden: Set<String>,
            extras: Set<String>
        ) -> String? {
            guard let tree else {
                if corpusCase.expectsError { recoveryCases += 1 } else { failed += 1 }
                return corpusCase.expectsError ? nil : ": the parse threw"
            }
            errors.add(tree)
            let visible = CorpusTreeNode.visibleNodes(of: tree.root, hidden: hidden)
            let actual =
                visible.count == 1
                ? visible[0].removing(extras) : CorpusTreeNode(type: "(no single root)", children: visible)
            if corpusCase.expectsError {
                recoveryCases += 1
                if actual == expected { recoveryMatched += 1 }
                return nil
            }
            guard let divergence = CorpusDivergence.first(expected: expected, actual: actual) else {
                matched += 1
                return nil
            }
            diverged += 1
            let text = divergence.actual?.byteRange
                .map { range in
                    String(
                        decoding: Array(tree.source.utf8)[range.clamped(to: 0 ..< tree.source.utf8.count)],
                        as: UTF8.self
                    )
                    .prefix(80).replacingOccurrences(of: "\n", with: "⏎")
                }
            return
                " at \(divergence.path.joined(separator: " > ")): expected \(divergence.expected?.sexp() ?? "nothing"), "
                + "got \(divergence.actual?.sexp() ?? "nothing")" + (text.map { " over “\($0)”" } ?? "")
        }

        var summary: String {
            let valid = matched + diverged + failed
            return "\(matched)/\(valid) valid cases match (\(diverged) diverge, \(failed) throw); "
                + "\(recoveryMatched)/\(recoveryCases) error-recovery cases match; \(skipped) skipped; "
                + errors.summary
        }
    }

    // MARK: - Large samples

    private func measureSamples(
        name: String, directory: URL, parser: GrammarParser, scannerType: (any GrammarExternalScanner.Type)?
    ) async throws {
        #expect(await LanguageHighlighter.ensureArtifacts(for: name))
        let clock = ContinuousClock()
        var total = ErrorCounts()
        for file in try Self.files(in: directory) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let start = clock.now
            let tree = try parser.parse(source, externalScanner: scannerType?.init())
            let parseTime = start.duration(to: clock.now)
            var counts = ErrorCounts()
            counts.add(tree)
            total.add(tree)
            let session = LanguageHighlighter.makeSession(language: name)
            _ = session.highlightDocument(source: source)
            print(
                "MEASURE \(name) sample \(file.lastPathComponent): \(source.utf8.count) bytes parsed in \(parseTime), "
                    + "\(counts.summary), grammar-highlighted \(session.isGrammarBacked)")
        }
        print("MEASURE \(name) samples: \(total.summary)")
    }

    // MARK: - Counting

    /// ERROR nodes and bytes over parses, and the nodes and bytes they are shares of.
    private struct ErrorCounts {
        var nodes = 0
        var errorNodes = 0
        var bytes = 0
        var errorBytes = 0

        mutating func add(_ tree: SyntaxTree) {
            var pending = [tree.root]
            while let node = pending.popLast() {
                nodes += 1
                if node.isError { errorNodes += 1 }
                pending.append(contentsOf: node.children)
            }
            bytes += tree.source.utf8.count
            errorBytes += tree.errorByteCount
        }

        var summary: String {
            "ERROR nodes \(errorNodes)/\(nodes) (\(Self.percent(errorNodes, nodes))), "
                + "ERROR bytes \(errorBytes)/\(bytes) (\(Self.percent(errorBytes, bytes)))"
        }

        private static func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "0%" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
        }
    }

    // MARK: - Environment

    /// The regular files under `directory`, sorted by path; none when it does not exist.
    private static func files(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// The process's physical footprint now and at its peak, in bytes; zeros if the kernel does not report them.
    private static func footprint() -> (current: Int, peak: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        // task_info writes integer_t words into the storage of the task_vm_info_data_t.
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (Int(info.phys_footprint), Int(info.ledger_phys_footprint_peak))
    }
}
