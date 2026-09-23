import Foundation

extension DiagnosticTool {
    /// Whether a tool reads the file at the root-relative `path` when it analyzes a tree: every Swift source, every
    /// tool's configuration file at any depth, the YAML files a SwiftLint configuration can pull in through
    /// `parent_config` or `child_config`, and `.swift-version`, which SwiftFormat reads. A tree exported for analysis
    /// holds these files and nothing else.
    public static func readsFile(at path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name.hasSuffix(".swift") || name.hasSuffix(".yml") || name.hasSuffix(".yaml") { return true }
        return name == ".swift-version" || allCases.contains { $0.configFileNames.contains(name) }
    }
}
