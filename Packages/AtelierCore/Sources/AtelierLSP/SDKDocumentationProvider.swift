public import AtelierSyntaxModel
import Darwin
public import Foundation
import os

/// Why the SDK tier's private probe directory could not be created.
public enum SDKProbeDirectoryError: Error, Sendable, Equatable {
    /// `mkdtemp(3)` failed under the parent directory at `parentPath`, with `code` as its `errno`.
    case creationFailed(parentPath: String, code: Int32)
}

/// On-device Apple SDK documentation through sourcekit-lsp: a synthetic document mirroring the hovered file's
/// imports probes the hovered identifier chain against the toolchain's own modules, with no network and no project
/// build context.
///
/// Each file resolves against its platform's SDK (``SDKPlatform/forFile(importing:inProjectDeclaring:)``): its imports
/// decide, then the manifests of the project it lies in, for a document on disk. One session serves each platform,
/// made on the platform's first hover; a platform whose session cannot be made, as iOS without Xcode, falls back to
/// the Mac's.
///
/// Declarations resolve reliably; prose appears only where the SDK's `.swiftdoc` carries it, so availability, the
/// online-only discussion and plain-comment Objective-C headers give none. A bare lowercase name with no receiver
/// is rejected before any request, and a query sends at most two probes. Answers, misses included, are cached in an
/// LRU keyed on the platform, the chain and its sorted imports, since the SDK cannot change under a running app. A
/// query whose probe got no answer, as from a cold server still loading the SDK's modules, is not cached, so the next
/// hover asks again.
public actor SDKDocumentationProvider: HoverProvider {
    /// Makes the session that resolves a platform's probes, or nil when the platform has none, as without its SDK.
    public typealias SessionFactory = @Sendable (SDKPlatform) async -> LanguageServerSession?

    private enum Session {
        case ready(LanguageServerSession?)
        /// Being made; the callers waiting on it.
        case making([CheckedContinuation<LanguageServerSession?, Never>])
    }

    private static let logger = Logger(subsystem: "Atelier.LSP", category: "SDKDocumentationProvider")

    private let makeSession: SessionFactory
    private let cacheCapacity: Int
    /// Whether an answer carries the symbol's page in Apple's developer documentation.
    private let resolvesDocumentationPages: Bool

    private var sessions: [SDKPlatform: Session] = [:]
    /// Set by ``shutdown()``: no session is made afterwards.
    private var isShutDown = false
    /// The platforms each directory's own manifests declare, keyed by the directory's path.
    private var directoryPlatforms: [String: Set<SDKPlatform>] = [:]

    /// Most recently used last in `order`; a `nil` value is a cached miss, which the server answered.
    private var cache: [CacheKey: HoverContent?] = [:]
    private var order: [CacheKey] = []

    /// Bumped per synthetic document, so concurrent probes never collide on the same URI.
    private var syntheticDocumentCounter = 0

    private struct CacheKey: Hashable {
        let platform: SDKPlatform
        let chain: String
        let imports: [String]
    }

    /// A provider over the sessions `makeSession` makes, one per platform, each on the platform's first hover.
    /// - Parameters:
    ///   - makeSession: Makes a platform's session, or nil when the platform has none.
    ///   - cacheCapacity: How many answers, misses included, the provider keeps.
    ///   - resolvesDocumentationPages: Whether an answer carries the symbol's page in Apple's developer documentation,
    ///     which takes the probe's session one or two more requests after its hover.
    public init(
        sessions makeSession: @escaping SessionFactory, cacheCapacity: Int = 256,
        resolvesDocumentationPages: Bool = false
    ) {
        self.makeSession = makeSession
        self.cacheCapacity = cacheCapacity
        self.resolvesDocumentationPages = resolvesDocumentationPages
    }

    /// A provider that resolves every platform's probes through `service`.
    public init(service: LanguageServerSession, cacheCapacity: Int = 256, resolvesDocumentationPages: Bool = false) {
        self.init(
            sessions: { _ in service }, cacheCapacity: cacheCapacity,
            resolvesDocumentationPages: resolvesDocumentationPages)
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        guard let extraction = Self.extractChain(in: query.content, line: query.line, utf16Column: query.utf16Column)
        else { return nil }

        let fileImports = Self.importedModules(in: query.content)
        let wanted = SDKPlatform.forFile(
            importing: fileImports, inProjectDeclaring: projectPlatforms(forDocumentAt: query.documentURI))
        guard let (platform, service) = await session(preferring: wanted) else { return nil }
        let imports = platform.probeImports(fileImports: fileImports, limit: Self.maximumProbeImports)
        let key = CacheKey(platform: platform, chain: extraction.chain, imports: imports)

        if let cached = cache[key] {
            touch(key)
            return cached
        }

        let result = await probeWithFallback(
            on: service, chain: extraction.chain, chainStartsUppercase: extraction.startsUppercase, imports: imports)
        if result.isSettled { store(key, result.content) }
        return result.content
    }

    /// Shuts down every session this provider made; a hover afterwards answers nothing.
    public func shutdown() async {
        isShutDown = true
        let current = sessions
        sessions.removeAll()
        var services: [LanguageServerSession] = []
        for session in current.values {
            switch session {
                case .ready(let service?): services.append(service)
                case .ready(nil): break
                case .making(let waiters): for waiter in waiters { waiter.resume(returning: nil) }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for service in services { group.addTask { await service.shutdown() } }
        }
    }

    // MARK: - Platforms and their sessions

    /// The session for `platform`, or the Mac's when `platform` has none; nil when neither has one.
    private func session(preferring platform: SDKPlatform) async -> (SDKPlatform, LanguageServerSession)? {
        if let service = await session(for: platform) { return (platform, service) }
        guard platform != .macOS, let service = await session(for: .macOS) else { return nil }
        return (.macOS, service)
    }

    /// `platform`'s session, made by the first caller while later ones wait for it, and kept, a nil one included.
    private func session(for platform: SDKPlatform) async -> LanguageServerSession? {
        switch sessions[platform] {
            case .ready(let service):
                return service
            case .making:
                return await withCheckedContinuation { continuation in
                    if case .making(let waiters) = sessions[platform] {
                        sessions[platform] = .making(waiters + [continuation])
                    } else {
                        // Unreachable without a suspension since the switch; resumed rather than leaked all the same.
                        continuation.resume(returning: nil)
                    }
                }
            case nil:
                guard !isShutDown else { return nil }
                sessions[platform] = .making([])
                let service = await makeSession(platform)
                guard case .making(let waiters) = sessions[platform] else {
                    // `shutdown()` ran meanwhile and answered the waiters.
                    await service?.shutdown()
                    return nil
                }
                if service == nil { Self.logger.info("No \(platform.rawValue, privacy: .public) SDK session") }
                sessions[platform] = .ready(service)
                for waiter in waiters { waiter.resume(returning: service) }
                return service
        }
    }

    /// The platforms the project of the document at `uri` declares: empty unless it is a file on disk. What each
    /// directory's manifests declare is read once, so files in sibling directories share their project's reading, and
    /// forgotten all at once past 512 directories; a manifest edited meanwhile counts from the app's next launch.
    private func projectPlatforms(forDocumentAt uri: String) -> Set<SDKPlatform> {
        guard let url = URL(string: uri), url.isFileURL else { return [] }
        return ProjectPlatforms.declared(forFileAt: url) { directory in
            if let known = directoryPlatforms[directory] { return known }
            if directoryPlatforms.count >= 512 { directoryPlatforms.removeAll() }
            let platforms = ProjectPlatforms.declared(inDirectory: directory)
            directoryPlatforms[directory] = platforms
            return platforms
        }
    }

    // MARK: - Probing

    /// The value-position probe's answer or, when it has no prose and the chain starts uppercase, a type-position
    /// probe's answer if that one has prose, or if the first found nothing, as for a protocol, which is no value.
    /// Settled only when every probe it sent was answered, since a probe that got none might have had prose. A first
    /// probe that gets no answer sends no second one: the server is not answering yet.
    private func probeWithFallback(
        on service: LanguageServerSession, chain: String, chainStartsUppercase: Bool, imports: [String]
    ) async -> (content: HoverContent?, isSettled: Bool) {
        let first = await probe(
            on: service, chain: chain, chainStartsUppercase: chainStartsUppercase, imports: imports,
            typePosition: false)
        guard case .answered(let primary) = first else { return (nil, false) }
        if let primary, HoverContentQuality.hasProse(primary.markdown) { return (primary, true) }
        guard chainStartsUppercase else { return (primary, true) }

        switch await probe(
            on: service, chain: chain, chainStartsUppercase: chainStartsUppercase, imports: imports,
            typePosition: true)
        {
            case .answered(let secondary?) where HoverContentQuality.hasProse(secondary.markdown):
                return (secondary, true)
            case .answered(let secondary):
                return (primary ?? secondary, true)
            case .unavailable:
                return (primary, false)
        }
    }

    /// One probe on `service`, whose document is named under the session's workspace root, its probe directory.
    private func probe(
        on service: LanguageServerSession, chain: String, chainStartsUppercase: Bool, imports: [String],
        typePosition: Bool
    ) async -> HoverOutcome {
        // A session reconnects on its next hover, so one that `shutdown()` ended while this query waited on its first
        // probe would otherwise start a server again, in a probe directory its owner is removing.
        guard !isShutDown else { return .unavailable }
        syntheticDocumentCounter += 1
        let uri = service.workspaceRoot.appending(path: "probe-\(syntheticDocumentCounter).swift").absoluteString

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
        let page =
            resolvesDocumentationPages
            ? await service.documentationPage(
                uri: uri, languageID: "swift", content: content, line: probeLineIndex, utf16Column: column) : nil
        return .answered(HoverContent(markdown: hover.markdown, source: .sdk, documentationPage: page))
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

    /// The top-level module of each import declaration in `content`, in order and without repeats.
    ///
    /// Reads the text's UTF-8 once and makes a string for an imported module's name alone. A line declares an import
    /// when, past its indentation, attributes (`@testable`, `@_spi(Name)`) and an access modifier (`public`), it reads
    /// `import`; the module is the first component of the path that follows any import kind (`struct`, `func`).
    static func importedModules(in content: String) -> [String] {
        var text = content
        return text.withUTF8 { bytes in
            var modules: [String] = []
            // A byte-order mark would read as the first line's first character, hiding that line's import.
            var lineStart = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            while lineStart < bytes.count {
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
}

// MARK: - Scratch sessions

extension SDKDocumentationProvider {
    /// A provider over scratch sessions of `serverExecutable`, one per platform, each rooted at `probeDirectory`, which
    /// every probe document is named under. The probes send their content inline and never read the workspace, so the
    /// empty directory serves as sourcekit-lsp's `rootUri`. The caller owns the directory, and removes it once
    /// ``shutdown()`` has returned. `locateSDK` finds a platform's SDK when its session is first needed, for every
    /// platform but the Mac, whose SDK the server finds itself; a platform whose SDK it does not find has no session.
    /// `resolvesDocumentationPages` makes each answer carry its symbol's page in Apple's developer documentation.
    public static func scratch(
        serverExecutable: URL, probeDirectory: URL,
        locateSDK: @escaping @Sendable (SDKPlatform) async -> SDKLocation?,
        idleShutdown: Duration = .seconds(180), requestTimeout: Duration = .seconds(2),
        resolvesDocumentationPages: Bool = false
    ) -> SDKDocumentationProvider {
        SDKDocumentationProvider(
            sessions: { platform in
                var sdk: SDKLocation?
                if platform != .macOS {
                    guard let located = await locateSDK(platform) else { return nil }
                    sdk = located
                }
                return LanguageServerSession(
                    configuration: scratchConfiguration(
                        for: platform, sdk: sdk, serverExecutable: serverExecutable, probeDirectory: probeDirectory,
                        idleShutdown: idleShutdown, requestTimeout: requestTimeout))
            }, resolvesDocumentationPages: resolvesDocumentationPages)
    }

    /// The configuration of `platform`'s scratch session: background indexing off, as for every hover session, and,
    /// given an `sdk`, sourcekit-lsp's fallback build settings, which a probe document gets since it belongs to no
    /// build system: that SDK, and a `-target` for it.
    public static func scratchConfiguration(
        for platform: SDKPlatform, sdk: SDKLocation?, serverExecutable: URL, probeDirectory: URL,
        idleShutdown: Duration = .seconds(180), requestTimeout: Duration = .seconds(2)
    ) -> LanguageServerSession.Configuration {
        var options: [String: JSONValue] = [:]
        if case .object(let hoverOptions) = LanguageServerSession.Configuration.hoverInitializationOptions {
            options = hoverOptions
        }
        if let sdk, let target = platform.targetTriple(sdkVersion: sdk.version) {
            options["fallbackBuildSystem"] = .object([
                "sdk": .string(sdk.path), "swiftCompilerFlags": .array([.string("-target"), .string(target)])
            ])
        }
        return LanguageServerSession.Configuration(
            serverExecutable: serverExecutable, workspaceRoot: probeDirectory, idleShutdown: idleShutdown,
            requestTimeout: requestTimeout, initializationOptions: .object(options))
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
