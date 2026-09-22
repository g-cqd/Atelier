public import AtelierSyntaxModel
public import Foundation

/// On-device Apple SDK documentation through sourcekit-lsp: a synthetic document mirroring the hovered file's
/// imports probes the identifier against the toolchain's own modules -- no network, no project build context.
///
/// ## Mechanics
/// 1. Extract the hovered identifier and its dotted chain (e.g. `NSVisualEffectView.Material.hudWindow`) by
///    scanning the hovered line around `utf16Column` for `[A-Za-z0-9_$.]` runs, trimming leading/trailing dots.
/// 2. Fast-reject chains sourcekit-lsp could never resolve without more context: a bare lowercase-leading
///    identifier with no dot (a member name without a receiver, e.g. hovering `hudWindow` alone) returns `nil`
///    before any LSP traffic.
/// 3. Collect `import X` lines from the hovered document (deduped, capped at 12), unioned with
///    ``defaultImports``.
/// 4. Synthesize a scratch Swift file: the imports, then a probe expression built from the chain --
///    `let _ = <chain>` when the chain starts with an uppercase letter (a type or type-qualified member, which
///    resolves as an expression on its own), `let _ = { <chain> }` as a fallback so a call-shaped or
///    lowercase-rooted-but-import-qualified chain still parses as a closure body.
/// 5. `didOpen` the synthetic document at a fabricated `file://` URI under a scratch temp directory, hover at
///    the identifier's position within the synthesized probe line, and map any non-empty result to
///    ``HoverContent`` with ``HoverContent/Source-swift.enum/sdk``.
///
/// ## Limits (honest, live-verified against a real toolchain)
/// - Declarations resolve reliably; doc comments surface only when the SDK's `.swiftdoc` carries them.
/// - Availability annotations and the online-only long-form discussion Xcode shows are absent.
/// - Old plain-comment Objective-C headers give a declaration only, no prose.
/// - A bare member name with no receiver and no qualifying import (e.g. hovering `foo` in `x.foo`) is rejected
///   before any LSP call; only the qualified chain resolves.
///
/// ## Caching
/// An LRU keyed on `(chain, sorted imports)` caches both hits and misses (`nil` included), since a toolchain's
/// answer for a given chain+imports pair is immutable for the lifetime of the process -- the underlying SDK
/// does not change out from under a running app. Capacity is set at ``init(service:defaultImports:cacheCapacity:)``.
public actor SDKDocumentationProvider: HoverProvider {
    private let service: SourceKitLSPService
    private let defaultImports: [String]
    private let cacheCapacity: Int

    /// LRU cache: most-recently-used at the end of `order`. `nil` values are meaningful (a cached miss).
    private var cache: [CacheKey: HoverContent?] = [:]
    private var order: [CacheKey] = []

    /// Bumped per synthetic document, so concurrent probes never collide on the same URI.
    private var syntheticDocumentCounter = 0

    private struct CacheKey: Hashable {
        let chain: String
        let imports: [String]
    }

    public init(
        service: SourceKitLSPService,
        defaultImports: [String] = ["Foundation", "AppKit", "SwiftUI"],
        cacheCapacity: Int = 256
    ) {
        self.service = service
        self.defaultImports = defaultImports
        self.cacheCapacity = cacheCapacity
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        guard let extraction = Self.extractChain(in: query.content, line: query.line, utf16Column: query.utf16Column)
        else { return nil }

        let imports = Self.collectImports(in: query.content, unioning: defaultImports)
        let key = CacheKey(chain: extraction.chain, imports: imports)

        if let cached = cache[key] {
            touch(key)
            return cached
        }

        let result = await probe(
            chain: extraction.chain, chainStartsUppercase: extraction.startsUppercase, imports: imports)
        store(key, result)
        return result
    }

    // MARK: - Probing

    private func probe(chain: String, chainStartsUppercase: Bool, imports: [String]) async -> HoverContent? {
        syntheticDocumentCounter += 1
        let uri = "file:///tmp/atelier-sdk-probe/probe-\(syntheticDocumentCounter).swift"

        var lines: [String] = imports.map { "import \($0)" }
        let probeLineIndex = lines.count
        if chainStartsUppercase {
            lines.append("let _ = \(chain)")
        } else {
            lines.append("let _ = { \(chain) }")
        }
        let content = lines.joined(separator: "\n")

        // The probe line is `let _ = ` (8 characters) or `let _ = { ` (11 characters) followed by the chain;
        // hover at the chain's first character so sourcekit-lsp resolves the leading (outermost-qualifying)
        // symbol of the dotted chain.
        let prefix = chainStartsUppercase ? "let _ = " : "let _ = { "
        let column = prefix.utf16.count

        guard
            let hover = await service.hover(
                uri: uri, languageID: "swift", content: content, line: probeLineIndex, utf16Column: column),
            !hover.markdown.isEmpty
        else { return nil }
        return HoverContent(markdown: hover.markdown, source: .sdk)
    }

    // MARK: - Cache (LRU, including nil results)

    private func touch(_ key: CacheKey) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    private func store(_ key: CacheKey, _ value: HoverContent?) {
        if cache[key] == nil {
            if order.count >= cacheCapacity, !order.isEmpty {
                let evicted = order.removeFirst()
                cache.removeValue(forKey: evicted)
            }
            order.append(key)
        } else {
            touch(key)
        }
        cache[key] = value
    }

    // MARK: - Identifier / chain extraction (textual, not syntactic)

    struct ChainExtraction: Equatable {
        let chain: String
        let startsUppercase: Bool
    }

    /// Extracts the dotted identifier chain touching `(line, utf16Column)`, e.g. hovering anywhere in
    /// `NSVisualEffectView.Material.hudWindow` (including mid-chain, or on a trailing dot) yields the whole
    /// chain with leading/trailing dots trimmed. Returns `nil` when there is no identifier run under the
    /// position, or when the chain is a bare member name (no dot, lowercase-leading) that sourcekit-lsp could
    /// never resolve without a receiver -- rejected here so no LSP traffic is spent on it.
    static func extractChain(in content: String, line: Int, utf16Column: Int) -> ChainExtraction? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard line >= 0, line < lines.count, utf16Column >= 0 else { return nil }
        let lineText = Array(lines[line].utf16)
        guard utf16Column <= lineText.count else { return nil }

        func isChainUnit(_ unit: UInt16) -> Bool {
            let scalar = Unicode.Scalar(unit)
            guard let scalar else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$" || scalar == "."
        }

        // A hover exactly at end-of-line, or on trivia, still wants the run immediately to its left, matching
        // how editors report the cursor after the last character of a token.
        var probeColumn = utf16Column
        if probeColumn == lineText.count, probeColumn > 0, isChainUnit(lineText[probeColumn - 1]) {
            probeColumn -= 1
        }
        guard probeColumn < lineText.count, isChainUnit(lineText[probeColumn]) else { return nil }

        var start = probeColumn
        while start > 0, isChainUnit(lineText[start - 1]) { start -= 1 }
        var end = probeColumn
        while end < lineText.count, isChainUnit(lineText[end]) { end += 1 }

        var chain = String(utf16CodeUnits: Array(lineText[start ..< end]), count: end - start)
        while chain.hasPrefix(".") { chain.removeFirst() }
        while chain.hasSuffix(".") { chain.removeLast() }
        guard !chain.isEmpty else { return nil }

        guard let firstCharacter = chain.first else { return nil }
        let startsUppercase = firstCharacter.isUppercase
        let isDotted = chain.contains(".")

        // A bare, undotted, lowercase-leading name is a local identifier or a member name without its
        // receiver in view (e.g. hovering `hudWindow` alone, rather than `Material.hudWindow`); sourcekit-lsp
        // has nothing to resolve it against in a synthetic probe, so reject before any LSP call.
        guard isDotted || startsUppercase else { return nil }

        return ChainExtraction(chain: chain, startsUppercase: startsUppercase)
    }

    /// `import X` lines in `content` (leading whitespace tolerated, `@testable`/submodule imports skipped),
    /// deduped and unioned with `defaults`, capped at 12 total imports.
    static func collectImports(in content: String, unioning defaults: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        func add(_ module: String) {
            guard seen.insert(module).inserted else { return }
            result.append(module)
        }

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("import ") else { continue }
            let rest = line.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
            // Only take the top-level module name: `import Foundation.NSString` -> `Foundation`.
            guard let module = rest.split(separator: ".").first, !module.isEmpty else { continue }
            add(String(module))
            if result.count >= 12 { break }
        }
        for module in defaults {
            guard result.count < 12 else { break }
            add(module)
        }
        return result.sorted()
    }

    // MARK: - Scratch service convenience

    /// A ``SourceKitLSPService`` configured with a scratch temp-directory workspace root, suitable for
    /// ``SDKDocumentationProvider``'s synthetic probes: the workspace itself is never inspected for symbols,
    /// only used as sourcekit-lsp's `rootUri`, so any writable directory works.
    public static func makeScratchService(
        serverExecutable: URL,
        serverArguments: [String] = [],
        idleShutdown: Duration = .seconds(180),
        requestTimeout: Duration = .seconds(2)
    ) -> SourceKitLSPService {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atelier-sdk-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = SourceKitLSPService.Configuration(
            serverExecutable: serverExecutable, serverArguments: serverArguments, workspaceRoot: root,
            idleShutdown: idleShutdown, requestTimeout: requestTimeout)
        return SourceKitLSPService(configuration: configuration)
    }
}
