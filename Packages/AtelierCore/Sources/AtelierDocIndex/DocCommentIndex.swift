import SwiftParser
import SwiftSyntax

import func AemiRuntime.mapConcurrently
import class Foundation.ProcessInfo

/// One source file to index, keyed by a stable URI so re-indexing can skip unchanged content.
public struct DocIndexFile: Sendable, Hashable {
    public let uri: String
    public let content: String
    /// The git blob id of `content`, when known: a file indexed at the same blob id keeps its entries without its
    /// content being hashed or parsed again. Nil never matches, so the content is hashed instead.
    public let blobID: String?
    /// The sides of a comparison the file answers for.
    public let sides: DocIndexSides

    public init(uri: String, content: String, blobID: String? = nil, sides: DocIndexSides = .both) {
        self.uri = uri
        self.content = content
        self.blobID = blobID
        self.sides = sides
    }
}

/// The sides of a comparison a file belongs to. A lookup from one side lists only the files of that side, so a
/// hover on the new side never lists the old version of a declaration beside the new one, whether both sides are
/// refs or the file was renamed, and a hover on the old side never lists the new version.
public struct DocIndexSides: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let old = DocIndexSides(rawValue: 1 << 0)
    public static let new = DocIndexSides(rawValue: 1 << 1)
    /// A file that is the same on both sides, such as one outside the changeset; as a lookup's side, every file.
    public static let both: DocIndexSides = [.old, .new]
}

/// A documented declaration: its name, a body-free signature, and its doc comment rendered as markdown.
public struct DocEntry: Sendable, Equatable {
    /// The declared identifier, e.g. a function or type name, `"init"`, or `"subscript"`.
    public let name: String
    /// The declaration head with its body cut off, whitespace collapsed to single spaces.
    public let signature: String
    /// The doc comment with `///`/`/** */` markers stripped, as markdown.
    public let markdown: String
    public let uri: String
}

/// Documentation extracted from Swift doc comments, kept current by re-indexing only the files whose content
/// changed. Files parse side by side, off the actor, so lookups carry on while an update runs, and a lookup reads
/// one name's entries rather than every file's.
public actor DocCommentIndex {
    private struct FileState {
        /// The blob id the file was indexed at, when the caller gave one.
        let blobID: String?
        /// The content's hash, when the file was indexed without a blob id.
        let contentHash: Int?
        var sides: DocIndexSides
        let entries: [DocEntry]
    }

    private var files: [String: FileState] = [:]
    /// Every file's entries by name, then by URI.
    private var byName: [String: [String: [DocEntry]]] = [:]
    /// Turns one file's content into its entries.
    private nonisolated let extractor: @Sendable (_ uri: String, _ content: String) -> [DocEntry]

    public init() {
        self.init(extractor: Self.extractEntries(uri:content:))
    }

    /// An index that extracts entries with `extractor`, such as a spy counting the files parsed.
    public init(extractor: @escaping @Sendable (_ uri: String, _ content: String) -> [DocEntry]) {
        self.extractor = extractor
    }

    /// How many files the index holds.
    public var fileCount: Int { files.count }

    /// Replaces the corpus with `files`: every other file is dropped, and a file whose blob id or content is
    /// unchanged keeps its entries.
    /// - Throws: `CancellationError` when the calling task is cancelled; the files dropped by then stay dropped.
    public func update(files: [DocIndexFile]) async throws {
        try keepOnly(Dictionary(files.map { ($0.uri, $0.sides) }, uniquingKeysWith: { _, last in last }))
        try await upsert(files)
    }

    /// Adds `files`, or replaces the ones already indexed, keeping every other file. A file indexed at the same blob
    /// id, or without one and with the same content, keeps its entries and takes its new sides; the others are parsed
    /// side by side, off the actor.
    /// - Throws: `CancellationError` when the calling task is cancelled, parsing or not. Nothing lands then, so a
    ///   superseded update never overwrites a newer one.
    public func upsert(_ files: [DocIndexFile]) async throws {
        try Task.checkCancellation()
        var unchanged: [DocIndexFile] = []
        var changed: [(file: DocIndexFile, contentHash: Int?)] = []
        for file in files {
            let indexed = self.files[file.uri]
            if let blobID = file.blobID {
                if indexed?.blobID == blobID { unchanged.append(file) } else { changed.append((file, nil)) }
            } else {
                let hash = Self.hash(of: file.content)
                if indexed?.contentHash == hash { unchanged.append(file) } else { changed.append((file, hash)) }
            }
        }
        let extractor = extractor
        let limit = ProcessInfo.processInfo.activeProcessorCount
        let parsed = try await mapConcurrently(changed, limit: limit) { change in
            try Task.checkCancellation()
            return extractor(change.file.uri, change.file.content)
        }
        // The last check before anything lands, with no suspension until the files are in.
        try Task.checkCancellation()
        for file in unchanged {
            self.files[file.uri]?.sides = file.sides
        }
        for (change, entries) in zip(changed, parsed) {
            let file = change.file
            replace(
                file.uri,
                with: FileState(
                    blobID: file.blobID, contentHash: change.contentHash, sides: file.sides, entries: entries))
        }
    }

    /// Keeps only the files `sides` names, each answering for the sides given there, and drops every other file with
    /// its entries.
    /// - Throws: `CancellationError` when the calling task is cancelled, and then changes nothing.
    public func keepOnly(_ sides: [String: DocIndexSides]) throws {
        try Task.checkCancellation()
        for uri in files.keys.filter({ sides[$0] == nil }) {
            replace(uri, with: nil)
        }
        for (uri, fileSides) in sides {
            files[uri]?.sides = fileSides
        }
    }

    /// Those of `blobIDs`, URI to blob id, that are indexed at that blob id, so a caller can skip reading them.
    public func urisIndexed(atBlobIDs blobIDs: [String: String]) -> Set<String> {
        Set(blobIDs.compactMap { uri, blobID in files[uri]?.blobID == blobID ? uri : nil })
    }

    /// Puts `state` in place of the file at `uri`, or drops the file when `state` is nil, with its entries by name.
    private func replace(_ uri: String, with state: FileState?) {
        if let indexed = files[uri] {
            for name in Set(indexed.entries.map(\.name)) {
                byName[name]?[uri] = nil
                if byName[name]?.isEmpty == true { byName[name] = nil }
            }
        }
        files[uri] = state
        guard let state else { return }
        for (name, entries) in Dictionary(grouping: state.entries, by: \.name) {
            byName[name, default: [:]][uri] = entries
        }
    }

    /// Entries named exactly `name` in the files that answer for `side`, those of `preferringURI` first, the rest in a
    /// stable order. Other URIs' entries are deduplicated (see `collapsingHistoricalDuplicates`); `preferringURI`'s
    /// own are kept as they are, since a hover on an old blob asks about the revision it names.
    public func documentation(
        forIdentifier name: String, preferringURI uri: String?, side: DocIndexSides = .both
    ) -> [DocEntry] {
        let matches = matches(named: name, side: side)
        let sameURI = uri.map { queryURI in matches.filter { $0.uri == queryURI } } ?? []
        let otherURIs = uri == nil ? matches : matches.filter { $0.uri != uri }
        var combined = sameURI + Self.collapsingHistoricalDuplicates(otherURIs)
        combined.sort { lhs, rhs in
            if let uri {
                let lhsPreferred = lhs.uri == uri
                let rhsPreferred = rhs.uri == uri
                if lhsPreferred != rhsPreferred { return lhsPreferred }
            }
            if lhs.uri != rhs.uri { return lhs.uri < rhs.uri }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.signature < rhs.signature
        }
        return combined
    }

    /// Every entry named exactly `name` in a file that answers for `side`, from the name's bucket alone.
    func matches(named name: String, side: DocIndexSides) -> [DocEntry] {
        var matches: [DocEntry] = []
        for (uri, entries) in byName[name] ?? [:] where files[uri]?.sides.isDisjoint(with: side) == false {
            matches += entries
        }
        return matches
    }

    /// Drops an `atelier-blob://` entry, which is history, when a `file://` entry has the same underlying path, then
    /// collapses entries with the same normalized signature and markdown to one, preferring `file://`. Distinct
    /// declarations that only share a name or a signature are kept.
    private static func collapsingHistoricalDuplicates(_ entries: [DocEntry]) -> [DocEntry] {
        let filePaths = entries.compactMap { entry -> String? in
            guard entry.uri.hasPrefix("file://") else { return nil }
            return underlyingPath(from: entry.uri)
        }
        let survivingHistory = entries.filter { entry in
            guard entry.uri.hasPrefix("atelier-blob://"), let blobPath = underlyingPath(from: entry.uri) else {
                return true
            }
            return !filePaths.contains { isSameUnderlyingPath($0, blobPath) }
        }

        var bestByRendering: [String: DocEntry] = [:]
        var order: [String] = []
        for entry in survivingHistory {
            let key = normalizedWhitespace(entry.signature) + "\u{0}" + entry.markdown
            if let existing = bestByRendering[key] {
                if !existing.uri.hasPrefix("file://"), entry.uri.hasPrefix("file://") {
                    bestByRendering[key] = entry
                }
            } else {
                bestByRendering[key] = entry
                order.append(key)
            }
        }
        return order.compactMap { bestByRendering[$0] }
    }

    /// The path in an `atelier-blob://<oid>/<path>` or `file://<root>/<path>` URI; the `file://` one keeps its root,
    /// so callers compare suffixes.
    private static func underlyingPath(from uri: String) -> String? {
        if uri.hasPrefix("atelier-blob://") {
            let rest = uri.dropFirst("atelier-blob://".count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            return String(rest[rest.index(after: slash)...])
        }
        if uri.hasPrefix("file://") {
            var rest = String(uri.dropFirst("file://".count))
            while rest.hasPrefix("/") { rest.removeFirst() }
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// Whether two derived paths name the same file: equal outright, or one is a path-component-aligned suffix of
    /// the other (so `"repo/Sources/Foo.swift"` matches `"Sources/Foo.swift"` but not `"OldFoo.swift"`).
    private static func isSameUnderlyingPath(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let (shorter, longer) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard !shorter.isEmpty, longer.hasSuffix(shorter) else { return false }
        let boundary = longer.index(longer.endIndex, offsetBy: -shorter.count - 1)
        return longer[boundary] == "/"
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func hash(of content: String) -> Int {
        var hasher = Hasher()
        hasher.combine(content)
        return hasher.finalize()
    }

    /// The documented declarations of one Swift file, parsed with swift-syntax.
    public static func extractEntries(uri: String, content: String) -> [DocEntry] {
        let tree = Parser.parse(source: content)
        let visitor = DocCommentVisitor(uri: uri)
        visitor.walk(tree)
        return visitor.entries
    }
}

/// Walks a syntax tree collecting an entry for every named declaration that carries a doc comment.
private final class DocCommentVisitor: SyntaxVisitor {
    private let uri: String
    private(set) var entries: [DocEntry] = []

    init(uri: String) {
        self.uri = uri
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: "init", decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: "subscript", decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        addEntry(name: node.name.text, decl: DeclSyntax(node), trivia: node.leadingTrivia)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let markdown = Self.markdown(from: node.leadingTrivia) else { return .visitChildren }
        let signature = Self.signature(from: DeclSyntax(node))
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            entries.append(
                DocEntry(
                    name: Self.stripBackticks(pattern.identifier.text), signature: signature, markdown: markdown,
                    uri: uri))
        }
        return .visitChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let markdown = Self.markdown(from: node.leadingTrivia) else { return .visitChildren }
        let signature = Self.signature(from: DeclSyntax(node))
        for element in node.elements {
            entries.append(
                DocEntry(
                    name: Self.stripBackticks(element.name.text), signature: signature, markdown: markdown, uri: uri))
        }
        return .visitChildren
    }

    private func addEntry(name: String, decl: DeclSyntax, trivia: Trivia) {
        guard let markdown = Self.markdown(from: trivia) else { return }
        entries.append(
            DocEntry(
                name: Self.stripBackticks(name), signature: Self.signature(from: decl), markdown: markdown, uri: uri))
    }

    private static func stripBackticks(_ text: String) -> String {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count > 1 else { return text }
        return String(text.dropFirst().dropLast())
    }

    /// The declaration up to its first `{`, whitespace collapsed; a closure default value ahead of the body cuts it
    /// short.
    private static func signature(from decl: DeclSyntax) -> String {
        let text = decl.trimmedDescription
        let head = text.firstIndex(of: "{").map { text[text.startIndex ..< $0] } ?? text[...]
        return head.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The doc comment above a declaration, as markdown, or nil when there is none.
    private static func markdown(from trivia: Trivia) -> String? {
        var lines: [String] = []
        for piece in trivia.pieces {
            switch piece {
                case .docLineComment(let text):
                    lines.append(stripLineDoc(text))
                case .docBlockComment(let text):
                    lines.append(contentsOf: stripBlockDoc(text))
                default:
                    break
            }
        }
        while lines.first == "" { lines.removeFirst() }
        while lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func stripLineDoc(_ text: String) -> String {
        var line = text
        if line.hasPrefix("///") { line.removeFirst(3) }
        if line.hasPrefix(" ") { line.removeFirst() }
        return line
    }

    private static func stripBlockDoc(_ text: String) -> [String] {
        var body = text
        if body.hasPrefix("/**") { body.removeFirst(3) }
        if body.hasSuffix("*/") { body.removeLast(2) }
        let rawLines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return rawLines.enumerated()
            .map { index, rawLine in
                if index == 0 {
                    return rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                }
                var line = Substring(rawLine.drop { $0 == " " || $0 == "\t" })
                if line.hasPrefix("*") {
                    line = line.dropFirst()
                    if line.hasPrefix(" ") { line = line.dropFirst() }
                }
                return String(line)
            }
    }
}
