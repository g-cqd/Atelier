import AemiJSON
public import Foundation

/// Decodes SARIF 2.1.0 logs into ``Finding``s. Only the subset of the schema the diagnostic tools emit is read.
///
/// Walks AemiJSON's lazy tape in one pass and materializes only the fields a ``Finding`` keeps; a Codable mirror
/// is about seven times slower on corpus-scale logs.
public enum SARIFDecoder {
    public enum DecodeError: Error, Equatable {
        case invalidJSON(String)
    }

    /// Parses `data` as a SARIF log and returns its findings for `tool`, with locations made relative to `root`.
    /// Results with no resolvable location are dropped; they carry nothing a `Finding` can anchor on.
    public static func findings(from data: Data, tool: DiagnosticTool, root: URL) throws(DecodeError) -> [Finding] {
        let doc: JSONDocument
        do {
            doc = try AemiJSON.parse(data)
        } catch {
            throw DecodeError.invalidJSON(String(describing: error))
        }
        let runs = doc.root["runs"]
        guard runs.isArray else {
            throw DecodeError.invalidJSON("expected a SARIF log with a top-level 'runs' array")
        }
        var findings: [Finding] = []
        runs.forEachElement { run in
            run["results"]
                .forEachElement { result in
                    guard let finding = Self.finding(from: result, tool: tool, root: root) else { return }
                    findings.append(finding)
                }
        }
        return findings
    }

    private static func finding(from result: JSON, tool: DiagnosticTool, root: URL) -> Finding? {
        let physical = result["locations"][index: 0]["physicalLocation"]
        guard let uri = physical["artifactLocation"]["uri"].string else { return nil }
        let region = physical["region"]
        var related: [RelatedLocation] = []
        result["relatedLocations"]
            .forEachElement { relatedLocation in
                let relatedPhysical = relatedLocation["physicalLocation"]
                guard let relatedURI = relatedPhysical["artifactLocation"]["uri"].string else { return }
                related.append(
                    RelatedLocation(
                        file: relativePath(of: relatedURI, root: root),
                        line: relatedPhysical["region"]["startLine"].int ?? 1,
                        message: relatedLocation["message"]["text"].string
                    ))
            }
        return Finding(
            tool: tool,
            ruleID: result["ruleId"].string ?? "",
            message: result["message"]["text"].string ?? "",
            file: relativePath(of: uri, root: root),
            line: region["startLine"].int ?? 1,
            column: region["startColumn"].int,
            endLine: region["endLine"].int,
            endColumn: region["endColumn"].int,
            severity: severity(for: result["level"].string),
            related: related
        )
    }

    private static func severity(for level: String?) -> Finding.Severity {
        switch level {
            case "error": .error
            case "warning": .warning
            case "note", "none": .note
            default: .warning
        }
    }

    /// Turns a SARIF artifact URI into an analysis-root-relative path: an absolute `file://` URI is stripped of
    /// `root`'s prefix, or kept whole when it falls outside `root`; a relative URI is used as-is.
    private static func relativePath(of uri: String, root: URL) -> String {
        if uri.hasPrefix("file://") {
            let path = URL(string: uri)?.path ?? String(uri.dropFirst("file://".count))
            let rootPath = root.path
            if path.hasPrefix(rootPath) {
                var relative = String(path.dropFirst(rootPath.count))
                while relative.hasPrefix("/") { relative.removeFirst() }
                return relative
            }
            return path
        }
        if uri.hasPrefix("./") { return String(uri.dropFirst(2)) }
        return uri
    }
}
