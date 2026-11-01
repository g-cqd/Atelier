internal import AtelierProcess
internal import Foundation

// Fingerprints, findings and the cache of outcomes; apart from the type's file, to keep its type body within the 300
// lines SwiftLint allows.
extension DiagnosticsEngine {
    // MARK: - Fingerprints

    /// `tool`'s cache key for `request`, run with the binary at `locatedPath`.
    /// A request identified by content is keyed by that identity, which covers its configuration files, in place of
    /// its root and their dates: its root is a throwaway folder, and may not exist yet.
    func cacheKey(for tool: DiagnosticTool, request: Request, locatedPath: String) -> CacheKey {
        CacheKey(
            tool: tool,
            executablePath: locatedPath,
            executableModification: modificationDate(ofItemAt: locatedPath),
            configFingerprint: request.contentIdentity == nil ? configFingerprint(for: tool, root: request.root) : "",
            root: request.contentIdentity.map { "content:\($0)" } ?? canonicalRoot(request.root),
            payloadFingerprint: payloadFingerprint(for: tool, request: request)
        )
    }

    /// A fingerprint of `tool`'s configuration files at `root`: each configured name's size and modification date,
    /// or `absent` when it does not exist. Any change to a config file busts the cache.
    func configFingerprint(for tool: DiagnosticTool, root: URL) -> String {
        tool.configFileNames
            .map { name in
                let path = root.appending(path: name).path
                guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return "\(name)=absent" }
                let size = (attributes[.size] as? UInt64) ?? 0
                let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return "\(name)=\(size):\(modified)"
            }
            .joined(separator: "|")
    }

    /// `root` as an absolute, symlink-free path, so every spelling of one directory shares its cache entries.
    func canonicalRoot(_ root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// What is being analyzed: for a per-file tool the sorted `path=hash` pairs, so moving content between paths
    /// still changes it; for a corpus tool the corpus fingerprint, with the sorted paths added for a tool that scopes
    /// its own report, since its report depends on which files it was given.
    func payloadFingerprint(for tool: DiagnosticTool, request: Request) -> String {
        switch tool.scope {
            case .perFile:
                return request.files.map { "\($0.path)=\($0.contentHash)" }.sorted().joined(separator: ",")
            case .corpus:
                let corpus = request.corpusFingerprint ?? ""
                guard tool.scopesItsOwnReport else { return corpus }
                let scopedFiles = request.files.map(\.path).sorted().joined(separator: ",")
                return "\(corpus)|\(scopedFiles)"
        }
    }

    /// Why a tool's output could not be decoded, carried as the message for ``RunStatus/failed(_:)``.
    struct ParseFailure: Error {
        let message: String
    }

    /// What a failed run printed on standard error, or its exit status when it printed nothing there.
    static func failureMessage(of output: ProcessOutput) -> String {
        output.errorText.isEmpty ? "exit \(output.terminationStatus)" : output.errorText
    }

    /// The tool's output decoded per its format on the concurrent executor, so a large log never holds the engine.
    @concurrent
    static func parsedFindings(
        from output: ProcessOutput,
        tool: DiagnosticTool,
        root: URL
    ) async -> Result<[Finding], ParseFailure> {
        switch tool.outputFormat {
            case .sarif:
                do {
                    return .success(try SARIFDecoder.findings(from: output.standardOutput, tool: tool, root: root))
                } catch {
                    return .failure(ParseFailure(message: String(describing: error)))
                }
            case .xcodeTextOnStderr:
                let stderrText = String(decoding: output.standardError, as: UTF8.self)
                let stdoutText = String(decoding: output.standardOutput, as: UTF8.self)
                return .success(
                    XcodeTextParser.findings(from: stderrText, tool: tool, root: root)
                        + XcodeTextParser.findings(from: stdoutText, tool: tool, root: root)
                )
        }
    }

    /// Narrows a corpus tool's findings to the requested files. A per-file tool only ran on those, and a tool that
    /// ``DiagnosticTool/scopesItsOwnReport`` already scoped its report to them, so its findings are kept as written.
    func filterFindings(_ findings: [Finding], tool: DiagnosticTool, request: Request) -> [Finding] {
        guard tool.scope == .corpus, !tool.scopesItsOwnReport else { return findings }
        let paths = Set(request.files.map(\.path))
        return findings.filter { paths.contains($0.file) }
    }

    func modificationDate(ofItemAt path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: - Cache

    func cachedOutcome(for key: CacheKey) -> CachedOutcome? {
        guard let outcome = cache[key] else { return nil }
        touch(key)
        return outcome
    }

    func store(_ outcome: CachedOutcome, for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheCapacity {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        } else {
            touch(key)
        }
        cache[key] = outcome
    }

    func touch(_ key: CacheKey) {
        guard let index = cacheOrder.firstIndex(of: key) else { return }
        cacheOrder.remove(at: index)
        cacheOrder.append(key)
    }
}
