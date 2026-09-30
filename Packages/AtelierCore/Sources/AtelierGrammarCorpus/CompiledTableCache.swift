import AtelierGrammar
import CryptoKit
import Darwin
import Foundation

/// Compiled grammar tables, and the errors of compiles that failed, on disk: one file per grammar file and compiler
/// version, so a relaunch neither compiles a grammar again nor retries one that cannot compile.
struct CompiledTableCache: Sendable {
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

    /// How a cache file holds tables.
    enum Format: Sendable {
        /// A table file (``ParseTableCompiler/CompilationResult/tableFile()``): compact, and read in a few copies.
        case binary
        /// The tables' JSON, which an older cache held: kept to measure the two against each other.
        case json

        /// The format `ATELIER_TABLE_CACHE_FORMAT` names: `json` for JSON, anything else or nothing for binary.
        static let current: Format =
            ProcessInfo.processInfo.environment["ATELIER_TABLE_CACHE_FORMAT"] == "json"
            ? .json : .binary
    }

    let directory: URL
    var format = Format.current

    /// The tables or the compile error stored for `key`; nil when neither is there or readable, or when the tables
    /// point outside themselves, which a damaged file can do and which would trap the parser on every launch. A table
    /// file that is damaged, cut short, of another version or not a table file at all reads as nil too.
    func outcome(for key: Key) -> Result<ParseTableCompiler.CompilationResult, GrammarError>? {
        if let data = storedTables(for: key),
            let tables = try? decode(data),
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

    /// The size in bytes of the tables file stored for `key`; nil when there is none. One `stat(2)`: nothing is read.
    func tableFileSize(for key: Key) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL(for: key, kind: .tables).path)
        return (attributes?[.size] as? NSNumber)?.intValue
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
                try encode(tables).write(to: fileURL(for: key, kind: .tables), options: .atomic)
            case .failure(let error):
                try SyntaxJSON.encode(RecordedFailure(error))
                    .write(to: fileURL(for: key, kind: .failure), options: .atomic)
        }
    }

    /// The bytes of the tables file stored for `key`: a table file read by ``contents(of:)``, JSON read whole.
    private func storedTables(for key: Key) -> Data? {
        let url = fileURL(for: key, kind: .tables)
        return switch format {
            case .binary: Self.contents(of: url)
            case .json: try? Data(contentsOf: url)
        }
    }

    private func encode(_ tables: ParseTableCompiler.CompilationResult) throws -> Data {
        switch format {
            case .binary: tables.tableFile()
            case .json: try GrammarRegistry.encodeCompiledTables(tables)
        }
    }

    private func decode(_ data: Data) throws -> ParseTableCompiler.CompilationResult {
        switch format {
            case .binary: try ParseTableCompiler.CompilationResult(tableFile: data)
            case .json: try GrammarRegistry.decodeCompiledTables(from: data)
        }
    }

    enum FileKind {
        case tables
        case failure
    }

    /// Where `key`'s file of `kind` is: a table file ends in `.tables`, the JSON of tables in `.ptable`.
    func fileURL(for key: Key, kind: FileKind) -> URL {
        let suffix =
            switch kind {
                case .tables: format == .binary ? "tables" : "ptable"
                case .failure: "failed"
            }
        return directory.appendingPathComponent("\(key.fileStem).\(suffix)")
    }
}

extension CompiledTableCache {
    /// The largest table file ``contents(of:)`` reads: 64 MiB, seven times the largest bundled grammar's, so a foreign
    /// file in the cache directory costs no more than a miss.
    static let maximumFileSize = 64 << 20

    /// The whole file at `url`; nil when it can't be read whole, is empty, is past ``maximumFileSize``, or changes size
    /// as it is read.
    ///
    /// The bytes go in memory mapped for this read alone, and unmapped when the data is released. A block of the heap
    /// would stay in the allocator's cache once freed, and counted in the process's footprint as long as the process
    /// runs: 9 MB for TypeScript's table file, as much as its tables once read.
    static func contents(of url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_size > 0, status.st_size <= maximumFileSize,
            let size = Int(exactly: status.st_size),
            let memory = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), memory != MAP_FAILED
        else { return nil }
        // Owner: this function, until the data below takes the mapping and unmaps it when released. Bounds: each read
        // writes at most the `size - filled` bytes left of the `size` mapped, from `memory + filled` on.
        var filled = 0
        while filled < size {
            let count = read(descriptor, memory + filled, size - filled)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            filled += count
        }
        guard filled == size else {
            munmap(memory, size)
            return nil
        }
        return Data(
            bytesNoCopy: memory, count: size, deallocator: .custom { pointer, count in _ = munmap(pointer, count) })
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
