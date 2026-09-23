import AtelierGrammar
import CryptoKit
import Foundation

/// Compiled grammar tables, and the errors of compiles that failed, on disk: one file per grammar file and compiler
/// version, so a relaunch neither compiles a grammar again nor retries one that cannot compile.
struct CompiledTableCache: Sendable {
    /// Where `GrammarRegistry.shared` keeps its files.
    static let defaultDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("kittycode-cache")

    /// What the outcome of a compile depends on: the grammar file's bytes and the compiler's format version.
    struct Key: Hashable, Sendable {
        /// `<language>-<16 hex digits of the grammar's SHA-256>-v<format version>`, safe as a file name.
        let fileStem: String

        init(language: String, grammar contents: Data) {
            let digest = SHA256.hash(data: contents).prefix(8).map { String(format: "%02x", $0) }.joined()
            let name = String(language.unicodeScalars.prefix(64).map(Self.fileNameCharacter))
            fileStem = "\(name)-\(digest)-v\(ParseTableCompiler.formatVersion)"
        }

        /// `scalar` when it is safe in a file name, `_` otherwise: a language name comes from an untrusted manifest.
        private static func fileNameCharacter(_ scalar: Unicode.Scalar) -> Character {
            let isSafe = scalar.isASCII && (scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar))
            return isSafe || scalar == "-" || scalar == "_" ? Character(scalar) : "_"
        }
    }

    let directory: URL

    /// The tables or the compile error stored for `key`; nil when neither is there or readable, or when the tables
    /// point outside themselves, which a damaged file can do and which would trap the parser on every launch.
    func outcome(for key: Key) -> Result<ParseTableCompiler.CompilationResult, GrammarError>? {
        if let data = try? Data(contentsOf: fileURL(for: key, kind: .tables)),
            let tables = try? GrammarRegistry.decodeCompiledTables(from: data),
            tables.isConsistent
        {
            return .success(tables)
        }
        if let data = try? Data(contentsOf: fileURL(for: key, kind: .failure)),
            let error = (try? SyntaxJSON.decode(RecordedFailure.self, from: data))?.error
        {
            return .failure(error)
        }
        return nil
    }

    /// Stores `outcome` for `key`. The cache only saves work, so a write that fails is dropped: the next launch
    /// compiles again.
    func store(_ outcome: Result<ParseTableCompiler.CompilationResult, GrammarError>, for key: Key) {
        try? write(outcome, for: key)
    }

    private func write(_ outcome: Result<ParseTableCompiler.CompilationResult, GrammarError>, for key: Key) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch outcome {
            case .success(let tables):
                try GrammarRegistry.encodeCompiledTables(tables)
                    .write(to: fileURL(for: key, kind: .tables), options: .atomic)
            case .failure(let error):
                try SyntaxJSON.encode(RecordedFailure(error))
                    .write(to: fileURL(for: key, kind: .failure), options: .atomic)
        }
    }

    private enum FileKind: String {
        case tables = "ptable"
        case failure = "failed"
    }

    private func fileURL(for key: Key, kind: FileKind) -> URL {
        directory.appendingPathComponent("\(key.fileStem).\(kind.rawValue)")
    }
}

/// A compile error as a cache file holds it.
private struct RecordedFailure: Codable {
    var kind: String
    var detail: String
}

extension RecordedFailure {
    init(_ error: GrammarError) {
        switch error {
            case .fileNotFound(let detail): self.init(kind: "fileNotFound", detail: detail)
            case .invalidJSON(let detail): self.init(kind: "invalidJSON", detail: detail)
            case .missingField(let detail): self.init(kind: "missingField", detail: detail)
            case .invalidRuleType(let detail): self.init(kind: "invalidRuleType", detail: detail)
            case .resourceLimitExceeded(let detail): self.init(kind: "resourceLimitExceeded", detail: detail)
            case .unsupportedVersion(let version): self.init(kind: "unsupportedVersion", detail: String(version))
        }
    }

    /// The error recorded; nil for a kind this version does not know.
    var error: GrammarError? {
        switch kind {
            case "fileNotFound": .fileNotFound(detail)
            case "invalidJSON": .invalidJSON(detail)
            case "missingField": .missingField(detail)
            case "invalidRuleType": .invalidRuleType(detail)
            case "resourceLimitExceeded": .resourceLimitExceeded(detail)
            case "unsupportedVersion": Int(detail).map(GrammarError.unsupportedVersion)
            default: nil
        }
    }
}
