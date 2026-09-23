import AemiTestKit
import Foundation
import Testing

@testable import AtelierProcess

struct ExecutableResolverTests {
    @Test
    func `the override variable wins when it names an executable`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let tool = directory.file("tool")
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: tool))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            let resolver = ExecutableResolver(overrideVariable: "TOOL_OVERRIDE", searchesPath: false)
            #expect(resolver.resolve("tool", environment: ["TOOL_OVERRIDE": tool]).path == tool)
            // A non-executable override is ignored.
            let plain = directory.file("plain")
            try Data().write(to: URL(filePath: plain))
            #expect(resolver.resolve("tool", environment: ["TOOL_OVERRIDE": plain]).path == "/usr/bin/tool")
        }
    }

    @Test
    func `search paths are tried in order after the PATH and excluded directories are skipped`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let first = directory.file("first")
            let second = directory.file("second")
            for dir in [first, second] {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let tool = dir + "/tool"
                try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: tool))
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            }
            let resolver = ExecutableResolver(searchPaths: [first, second], excludedPaths: [first])
            #expect(resolver.resolve("tool", environment: [:]).path == second + "/tool")
            let fromPath = ExecutableResolver(searchPaths: [second])
            #expect(fromPath.resolve("tool", environment: ["PATH": first]).path == first + "/tool")
        }
    }

    @Test
    func `nothing found resolves to the fallback directory`() {
        let resolver = ExecutableResolver(searchPaths: ["/nonexistent"], searchesPath: false, fallbackPath: "/opt/x")
        #expect(resolver.resolve("tool", environment: [:]).path == "/opt/x/tool")
    }

    /// `path`, absolute, spelled relative to the process's working directory: enough `..` to reach `/`, then the rest,
    /// so it names the same file wherever the tests run.
    private static func relativeSpelling(of path: String) -> String {
        let depth = FileManager.default.currentDirectoryPath.split(separator: "/").count
        return String(repeating: "../", count: depth) + path.dropFirst()
    }

    @Test
    func `a relative, empty or dot PATH entry is never searched, even when it reaches the tool`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let bin = directory.file("bin")
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: bin + "/tool"))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin + "/tool")
            let relative = Self.relativeSpelling(of: bin)
            #expect(FileManager.default.isExecutableFile(atPath: relative + "/tool"))

            let resolver = ExecutableResolver(searchPaths: [relative], fallbackPath: "/opt/x")
            #expect(resolver.resolve("tool", environment: ["PATH": ".::\(relative)"]).path == "/opt/x/tool")
        }
    }

    @Test
    func `a relative override is never used, even when it names the tool`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let tool = directory.file("tool")
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: tool))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            let relative = Self.relativeSpelling(of: tool)
            #expect(FileManager.default.isExecutableFile(atPath: relative))

            let resolver = ExecutableResolver(
                overrideVariable: "TOOL_OVERRIDE", searchesPath: false, fallbackPath: "/opt/x")
            #expect(resolver.resolve("tool", environment: ["TOOL_OVERRIDE": relative]).path == "/opt/x/tool")
        }
    }
}
