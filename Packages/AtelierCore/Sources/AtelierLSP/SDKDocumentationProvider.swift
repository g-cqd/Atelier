public import AtelierSyntaxModel
import Darwin
public import Foundation

/// Why the SDK tier's private probe directory could not be created.
public enum SDKProbeDirectoryError: Error, Sendable, Equatable {
    /// `mkdtemp(3)` failed under the parent directory at `parentPath`, with `code` as its `errno`.
    case creationFailed(parentPath: String, code: Int32)
}

/// On-device Apple SDK documentation through sourcekit-lsp: a synthetic document mirroring the hovered file's
/// imports probes the hovered identifier chain against the toolchain's own modules, with no network and no project
/// build context.
///
/// Declarations resolve reliably; prose appears only where the SDK's `.swiftdoc` carries it, so availability, the
/// online-only discussion and plain-comment Objective-C headers give none. A bare lowercase name with no receiver
/// is rejected before any request, and a query sends at most two probes. Answers, misses included, are cached in an
/// LRU keyed on the chain and its sorted imports, since the SDK cannot change under a running app. A query whose
/// probe got no answer, as from a cold server still loading the SDK's modules, is not cached, so the next hover asks
/// again.
public actor SDKDocumentationProvider: HoverProvider {
    private let service: SourceKitLSPService
    /// The directory every probe document is named under: the service's workspace root.
    private let probeRoot: URL
    private let defaultImports: [String]
    private let cacheCapacity: Int

    /// Most recently used last in `order`; a `nil` value is a cached miss, which the server answered.
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
        probeRoot = service.workspaceRoot
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

        let result = await probeWithFallback(
            chain: extraction.chain, chainStartsUppercase: extraction.startsUppercase, imports: imports)
        if result.isSettled { store(key, result.content) }
        return result.content
    }

    // MARK: - Probing

    /// The value-position probe's answer or, when it has no prose and the chain starts uppercase, a type-position
    /// probe's answer if that one has prose. Settled only when every probe it sent was answered, since a probe that
    /// got none might have had prose. A first probe that gets no answer sends no second one: the server is not
    /// answering yet.
    private func probeWithFallback(chain: String, chainStartsUppercase: Bool, imports: [String]) async
        -> (content: HoverContent?, isSettled: Bool)
    {
        let first = await probe(
            chain: chain, chainStartsUppercase: chainStartsUppercase, imports: imports, typePosition: false)
        guard case .answered(let primary) = first else { return (nil, false) }
        if let primary, HoverContentQuality.hasProse(primary.markdown) { return (primary, true) }
        guard chainStartsUppercase else { return (primary, true) }

        switch await probe(
            chain: chain, chainStartsUppercase: chainStartsUppercase, imports: imports, typePosition: true)
        {
            case .answered(let secondary?) where HoverContentQuality.hasProse(secondary.markdown):
                return (secondary, true)
            case .answered:
                return (primary, true)
            case .unavailable:
                return (primary, false)
        }
    }

    private func probe(chain: String, chainStartsUppercase: Bool, imports: [String], typePosition: Bool) async
        -> HoverOutcome
    {
        syntheticDocumentCounter += 1
        let uri = probeRoot.appending(path: "probe-\(syntheticDocumentCounter).swift").absoluteString

        var lines: [String] = imports.map { "import \($0)" }
        let probeLineIndex = lines.count
        let prefix: String
        if typePosition {
            // Some toolchains resolve a value-position `let _ = Type` to its initializer overloads; a `typealias`
            // target is unambiguously the type.
            prefix = "typealias _AtelierProbe = "
            lines.append("\(prefix)\(chain)")
        } else if chainStartsUppercase {
            prefix = "let _ = "
            lines.append("\(prefix)\(chain)")
        } else {
            prefix = "let _ = { "
            lines.append("\(prefix)\(chain) }")
        }
        let content = lines.joined(separator: "\n")

        // sourcekit-lsp resolves a dotted expression per token, so the hover targets the chain's last segment.
        let column = prefix.utf16.count + Self.tailSegmentOffset(in: chain)

        let outcome = await service.hover(
            uri: uri, languageID: "swift", content: content, line: probeLineIndex, utf16Column: column)
        guard case .answered(let hover?) = outcome else { return outcome }
        return .answered(HoverContent(markdown: hover.markdown, source: .sdk))
    }

    /// The UTF-16 offset, within `chain`, of its last dot-separated segment's first character; `0` when `chain`
    /// has no dot.
    private static func tailSegmentOffset(in chain: String) -> Int {
        guard let lastDot = chain.lastIndex(of: ".") else { return 0 }
        return chain[chain.startIndex ... lastDot].utf16.count
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

    /// The whole dotted identifier chain touching `(line, utf16Column)`, trimmed of outer dots; nil when no chain is
    /// there or when it is a bare lowercase name, which a probe cannot resolve without its receiver.
    static func extractChain(in content: String, line: Int, utf16Column: Int) -> ChainExtraction? {
        guard utf16Column >= 0, let lineText = lineUnits(line, of: content), utf16Column <= lineText.count else {
            return nil
        }

        func isChainUnit(_ unit: UInt16) -> Bool {
            let scalar = Unicode.Scalar(unit)
            guard let scalar else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$" || scalar == "."
        }

        // A hover just past the line's last character still means the token before it.
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

        guard isDotted || startsUppercase else { return nil }

        return ChainExtraction(chain: chain, startsUppercase: startsUppercase)
    }

    /// The UTF-16 code units of line `index` of `content`, without its line break, a `\r\n` included; nil past the
    /// last line. Walks the text's UTF-8 up to the line once, and decodes that line alone.
    static func lineUnits(_ index: Int, of content: String) -> [UInt16]? {
        guard index >= 0 else { return nil }
        var text = content
        // `withUTF8` hands a native string's own storage over, and copies a bridged one once.
        return text.withUTF8 { bytes -> [UInt16]? in
            var start = 0
            for _ in 0 ..< index {
                guard let lineBreak = bytes[start...].firstIndex(of: newline) else { return nil }
                start = lineBreak + 1
            }
            var end = bytes[start...].firstIndex(of: newline) ?? bytes.count
            if end > start, bytes[end - 1] == carriageReturn { end -= 1 }
            return Array(String(decoding: bytes[start ..< end], as: UTF8.self).utf16)
        }
    }

    // MARK: - Imports

    /// The most modules a probe document imports.
    static let maximumProbeImports = 12

    /// The top-level modules `content` imports, then `defaults`: sorted, unique, and at most
    /// ``maximumProbeImports``, the file's own first.
    static func collectImports(in content: String, unioning defaults: [String]) -> [String] {
        var modules = importedModules(in: content, limit: maximumProbeImports)
        for module in defaults where modules.count < maximumProbeImports && !modules.contains(module) {
            modules.append(module)
        }
        return modules.sorted()
    }

    /// The top-level module of each import declaration in `content`, in order and without repeats, at most `limit`.
    ///
    /// Reads the text's UTF-8 once and makes a string for an imported module's name alone. A line declares an import
    /// when, past its indentation, attributes (`@testable`, `@_spi(Name)`) and an access modifier (`public`), it reads
    /// `import`; the module is the first component of the path that follows any import kind (`struct`, `func`).
    static func importedModules(in content: String, limit: Int = .max) -> [String] {
        var text = content
        return text.withUTF8 { bytes in
            var modules: [String] = []
            var lineStart = 0
            while lineStart < bytes.count, modules.count < limit {
                let lineEnd = bytes[lineStart...].firstIndex(of: newline) ?? bytes.count
                if let module = importedModule(on: bytes[lineStart ..< lineEnd]), !modules.contains(module) {
                    modules.append(module)
                }
                lineStart = lineEnd + 1
            }
            return modules
        }
    }

    /// A run of a string's UTF-8, borrowed for the length of a scan.
    private typealias UTF8Bytes = Slice<UnsafeBufferPointer<UInt8>>

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let accessModifiers = ["public", "package", "internal", "fileprivate", "private"]
    private static let importKinds = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]

    /// The module the import declaration on `line` names; nil when the line declares no import.
    private static func importedModule(on line: UTF8Bytes) -> String? {
        var rest = line.drop(while: isBlank)
        while rest.first == UInt8(ascii: "@") {
            rest = rest.dropFirst().drop(while: isIdentifierByte)
            if rest.first == UInt8(ascii: "(") {
                guard let close = rest.firstIndex(of: UInt8(ascii: ")")) else { return nil }
                rest = rest[rest.index(after: close)...]
            }
            rest = rest.drop(while: isBlank)
        }
        rest = dropKeyword(in: rest, from: accessModifiers) ?? rest
        guard let path = dropKeyword(in: rest, from: ["import"]) else { return nil }
        let module = (dropKeyword(in: path, from: importKinds) ?? path).prefix(while: isIdentifierByte)
        return module.isEmpty ? nil : String(decoding: module, as: UTF8.self)
    }

    /// `text` past its leading keyword, one of `keywords`, and the blanks after it; nil when `text` starts with none of
    /// them followed by a blank.
    private static func dropKeyword(in text: UTF8Bytes, from keywords: [String]) -> UTF8Bytes? {
        for keyword in keywords where text.starts(with: keyword.utf8) {
            let rest = text.dropFirst(keyword.utf8.count)
            guard let next = rest.first, isBlank(next) else { continue }
            return rest.drop(while: isBlank)
        }
        return nil
    }

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    /// An identifier's byte: an ASCII letter, digit or underscore, or any byte of a non-ASCII character.
    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"),
                UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"), 0x80...:
                true
            default:
                false
        }
    }

    // MARK: - Scratch service convenience

    /// A ``SourceKitLSPService`` rooted at a new private probe directory (``makeProbeDirectory(in:)``), which every
    /// probe document is named under. The probes send their content inline and never read the workspace, so the
    /// empty directory serves as sourcekit-lsp's `rootUri`. The caller owns the directory, and removes it once the
    /// service has shut down.
    /// - Throws: ``SDKProbeDirectoryError/creationFailed(parentPath:code:)`` when the directory cannot be created.
    public static func makeScratchService(
        serverExecutable: URL,
        serverArguments: [String] = [],
        idleShutdown: Duration = .seconds(180),
        requestTimeout: Duration = .seconds(2),
        parentDirectory: URL = FileManager.default.temporaryDirectory
    ) throws(SDKProbeDirectoryError) -> SourceKitLSPService {
        let root = try makeProbeDirectory(in: parentDirectory)
        let configuration = SourceKitLSPService.Configuration(
            serverExecutable: serverExecutable, serverArguments: serverArguments, workspaceRoot: root,
            idleShutdown: idleShutdown, requestTimeout: requestTimeout)
        return SourceKitLSPService(configuration: configuration)
    }

    /// Creates a new directory under `parent` with `mkdtemp(3)`: its name is unique, and only the current user can
    /// read, write or enter it (mode 0700), so no other account can plant a file under a probe document.
    /// - Throws: ``SDKProbeDirectoryError/creationFailed(parentPath:code:)`` when `mkdtemp` fails.
    public static func makeProbeDirectory(
        in parent: URL = FileManager.default.temporaryDirectory
    ) throws(SDKProbeDirectoryError) -> URL {
        let parentPath = parent.path(percentEncoded: false)
        var template = Array(parent.appending(path: "atelier-sdk-probe.XXXXXX").path(percentEncoded: false).utf8CString)
        // `mkdtemp` rewrites the trailing X's in place and returns its argument, or nil with `errno` set.
        let failure: Int32? = template.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return EINVAL }
            return mkdtemp(base) == nil ? errno : nil
        }
        if let failure { throw .creationFailed(parentPath: parentPath, code: failure) }
        let path = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
