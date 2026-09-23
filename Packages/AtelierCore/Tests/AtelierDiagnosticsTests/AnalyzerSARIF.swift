import AemiTestKit
import Foundation

/// SARIF as arcleak, dolly and deadwood write it without `--relative-to`: their `ReportFormatter`s' shape, encoded by
/// `JSONEncoder` pretty-printed with sorted keys, so every `/` in a path is escaped, and each `uri` a plain absolute
/// path as Foundation resolves it.
enum AnalyzerSARIF {
    /// One reported location: a path, and a 1-based line and column.
    struct Location {
        let path: String
        let line: Int
        let column: Int
    }

    /// One finding: its rule, level and message, where it is anchored, and the related locations it points to.
    struct Entry {
        let ruleID: String
        let level: String
        let message: String
        let location: Location
        var related: [Location] = []
        /// The label dolly gives every related location; nil for tools that give none.
        var relatedMessage: String?
    }

    /// The SARIF log `tool` prints for `results`.
    static func log(tool: String, results: [Entry]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let log = Log(
            runs: [
                Run(
                    tool: Tool(driver: Driver(name: tool, version: "0.9.0", informationUri: "https://example.com")),
                    results: results.map { result in
                        EncodedResult(
                            ruleId: result.ruleID, level: result.level, message: Text(text: result.message),
                            locations: [EncodedLocation(result.location)],
                            relatedLocations: result.related.isEmpty
                                ? nil
                                : result.related.map {
                                    EncodedLocation($0, message: result.relatedMessage.map(Text.init(text:)))
                                },
                            partialFingerprints: ["\(tool)/v1": "\(result.ruleID)-\(result.location.line)"])
                    })
            ])
        return String(decoding: try encoder.encode(log), as: UTF8.self)
    }

    private struct Log: Encodable {
        enum CodingKeys: String, CodingKey {
            case version
            case schema = "$schema"
            case runs
        }

        let version = "2.1.0"
        let schema = "https://json.schemastore.org/sarif-2.1.0.json"
        let runs: [Run]
    }

    private struct Run: Encodable {
        let tool: Tool
        let results: [EncodedResult]
    }

    private struct Tool: Encodable {
        let driver: Driver
    }

    private struct Driver: Encodable {
        let name: String
        let version: String
        let informationUri: String
    }

    private struct Text: Encodable {
        let text: String
    }

    private struct EncodedResult: Encodable {
        let ruleId: String
        let level: String
        let message: Text
        let locations: [EncodedLocation]
        let relatedLocations: [EncodedLocation]?
        let partialFingerprints: [String: String]
    }

    private struct EncodedLocation: Encodable {
        let physicalLocation: PhysicalLocation
        let message: Text?

        init(_ location: Location, message: Text? = nil) {
            physicalLocation = PhysicalLocation(
                artifactLocation: ArtifactLocation(uri: location.path),
                region: Region(startLine: location.line, startColumn: location.column))
            self.message = message
        }
    }

    private struct PhysicalLocation: Encodable {
        let artifactLocation: ArtifactLocation
        let region: Region
    }

    private struct ArtifactLocation: Encodable {
        let uri: String
    }

    private struct Region: Encodable {
        let startLine: Int
        let startColumn: Int
    }
}

/// A repository shaped like verify-deps' SARIF fixture: its name holds a space, it lives under `$TMPDIR`, and it is
/// opened through a symlink, so the root as opened, its physical path and the paths the analyzers print all differ.
struct AnalyzerRepository {
    private let temporary = TemporaryDirectory(prefix: "sarif-fx")

    /// The root as opened: a symlink to the repository.
    var root: URL { URL(filePath: temporary.file("link")) }

    /// Creates each of `files`, root-relative, empty, and the symlink the repository is opened through.
    init(files: [String]) throws {
        for file in files {
            let url = URL(filePath: temporary.file("My Repo/\(file)"))
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try FileManager.default.createSymbolicLink(
            atPath: temporary.file("link"), withDestinationPath: temporary.file("My Repo"))
    }

    func cleanup() {
        temporary.cleanup()
    }

    /// `file` as the analyzers print it: their `SourcePath.canonical`, which resolves the symlink and strips
    /// `/private`.
    func reportedPath(_ file: String) -> String {
        URL(fileURLWithPath: temporary.file("My Repo/\(file)")).standardized.resolvingSymlinksInPath().path
    }
}
